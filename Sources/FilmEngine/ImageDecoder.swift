import CoreGraphics
import CoreImage
import ImageIO
import Metal
import Foundation

struct ImageDecoder {
    let device: any MTLDevice
    let workingSpace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
    private let queue: any MTLCommandQueue
    /// Core Image is confined to RAW decoding and the colour-managed handoff.
    private let context: CIContext
    /// How much staging buffer the colour-managed draw may hold at once.
    let bandBytes: Int

    init(device: any MTLDevice, bandBytes: Int = 32 << 20) throws {
        self.device = device
        self.bandBytes = max(bandBytes, 1 << 20)
        guard let queue = device.makeCommandQueue() else { throw FilmError.invalid("Metal is unavailable") }
        self.queue = queue
        context = CIContext(mtlDevice: device, options: [.workingColorSpace: workingSpace, .cacheIntermediates: false])
    }

    /// `maximumDimension` downsamples in the linear Working Space for the Preview Render Path.
    func decode(_ data: Data, maximumDimension: Int? = nil) async throws -> any MTLTexture {
        if let maximumDimension, maximumDimension < 1 { throw FilmError.invalid("Preview dimension must be positive") }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw FilmError.invalid("Unsupported photo file")
        }
        let type = CGImageSourceGetType(source) as String? ?? ""
        if UTTypeConformsToRaw(type) {
            guard let raw = CIRAWFilter(imageData: data, identifierHint: type) else {
                throw FilmError.invalid("The system RAW decoder does not support this photo")
            }
            raw.isDraftModeEnabled = false
            let native = max(raw.nativeSize.width, raw.nativeSize.height)
            if let maximumDimension, native > CGFloat(maximumDimension) {
                raw.scaleFactor = Float(CGFloat(maximumDimension) / native)
            }
            // CIRAWFilter defaults to photographic tone/shadow boosts. They must
            // be disabled before the scene-referred Working Space handoff.
            raw.boostAmount = 0
            raw.shadowBias = 0
            raw.isGamutMappingEnabled = false
            raw.extendedDynamicRangeAmount = 1
            if raw.isLocalToneMapSupported { raw.localToneMapAmount = 0 }
            if raw.isContrastSupported { raw.contrastAmount = 0 }
            if raw.isDetailSupported { raw.detailAmount = 0 }
            if raw.isSharpnessSupported { raw.sharpnessAmount = 0 }
            if raw.isLuminanceNoiseReductionSupported { raw.luminanceNoiseReductionAmount = 0 }
            if raw.isColorNoiseReductionSupported { raw.colorNoiseReductionAmount = 0 }
            guard let image = raw.outputImage, !image.extent.isEmpty, !image.extent.isInfinite else { throw FilmError.invalid("RAW decode failed") }
            let texture = try makeTexture(width: Int(image.extent.width), height: Int(image.extent.height))
            // Render on an explicit command buffer and await it: with a nil buffer Core
            // Image commits asynchronously and later reads of the texture race the decode.
            guard let command = queue.makeCommandBuffer() else { throw FilmError.invalid("Cannot create decode command") }
            context.render(image, to: texture, commandBuffer: command, bounds: image.extent, colorSpace: workingSpace)
            try await withCheckedThrowingContinuation(Renderer.completion(command))
            return texture
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = image.colorSpace, space.model == .rgb || space.model == .monochrome else {
            throw FilmError.invalid("Photo has no supported input colour profile")
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let exif = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any]
        guard properties?[kCGImagePropertyProfileName] != nil || exif?[kCGImagePropertyExifColorSpace] as? Int == 1 else {
            // ImageIO supplies a default sRGB CGColorSpace even when the file has
            // no tag. The metadata must establish that assignment explicitly.
            throw FilmError.invalid("This photo has no colour profile; assign one before opening it")
        }
        let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
        let swapsAxes = (5...8).contains(orientation)
        var scale = 1.0
        if let maximumDimension, max(image.width, image.height) > maximumDimension {
            scale = Double(maximumDimension) / Double(max(image.width, image.height))
        }
        let drawWidth = max(1, Int((Double(image.width) * scale).rounded()))
        let drawHeight = max(1, Int((Double(image.height) * scale).rounded()))
        let width = swapsAxes ? drawHeight : drawWidth
        let height = swapsAxes ? drawWidth : drawHeight
        let texture = try makeTexture(width: width, height: height)
        // A band at a time rather than the whole frame at once.
        //
        // The whole-frame form held three full-size allocations simultaneously: a
        // Float32 staging buffer, a Float16 copy of it, and the destination texture.
        // For a 48MP frame that is 1.45GB resident before the Export has rendered a
        // Tile — four times the largest allocation `ImageWriter` reasons about, and
        // unaccounted for anywhere. Banding replaces the two staging buffers with one
        // band of each, and the conversion happens in the same pass as the
        // unpremultiply rather than as a second whole-frame map.
        //
        // The rows are the *destination's*, so a band is a band of the texture whatever
        // the EXIF orientation did to the axes; the orientation transform is composed
        // with a translation that puts the band's rows where the whole-frame draw would
        // have put them. `bandedDecodeMatchesAWholeFrameDecodeForEveryOrientation` is
        // the assertion that this is a memory change and not a pixel one.
        let bandRows = max(1, min(height, bandBytes / (width * 16)))
        var staging = [Float](repeating: 0, count: width * bandRows * 4)
        var half = [Float16](repeating: 0, count: width * bandRows * 4)
        var row = 0
        while row < height {
            let rows = min(bandRows, height - row)
            let count = width * rows * 4
            for index in 0..<count { staging[index] = 0 }
            try staging.withUnsafeMutableBytes { bytes in
                guard let context = CGContext(data: bytes.baseAddress, width: width, height: rows,
                    bitsPerComponent: 32, bytesPerRow: width * 16, space: workingSpace,
                    bitmapInfo: CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue |
                        CGImageAlphaInfo.premultipliedLast.rawValue) else {
                    throw FilmError.invalid("Cannot create colour-managed decode context")
                }
                // Core Graphics counts rows from the bottom and the texture upload from
                // the top, and the whole-frame form relied on that: buffer row 0 is
                // texture row 0. Shifting the drawing down by the band's start keeps
                // every band on the same footing.
                context.translateBy(x: 0, y: -CGFloat(row))
                // ImageIO exposes EXIF orientation separately from the decoded raster.
                switch orientation {
                case 2: context.translateBy(x: CGFloat(width), y: 0); context.scaleBy(x: -1, y: 1)
                case 3: context.translateBy(x: CGFloat(width), y: CGFloat(height)); context.rotate(by: .pi)
                case 4: context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
                case 5: context.rotate(by: -.pi / 2); context.scaleBy(x: -1, y: 1)
                case 6: context.translateBy(x: 0, y: CGFloat(height)); context.rotate(by: -.pi / 2)
                case 7: context.translateBy(x: CGFloat(width), y: CGFloat(height)); context.rotate(by: .pi / 2); context.scaleBy(x: -1, y: 1)
                case 8: context.translateBy(x: CGFloat(width), y: 0); context.rotate(by: .pi / 2)
                default: break
                }
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: 0, y: 0, width: drawWidth, height: drawHeight))
            }
            // CGContext is premultiplied; the Metal pipeline uses straight alpha. The
            // divide and the conversion to the Working Space's precision are one pass.
            for pixel in stride(from: 0, to: count, by: 4) {
                let alpha = staging[pixel + 3]
                if alpha > 0 {
                    for channel in 0..<3 { half[pixel + channel] = Float16(staging[pixel + channel] / alpha) }
                } else {
                    for channel in 0..<3 { half[pixel + channel] = Float16(staging[pixel + channel]) }
                }
                half[pixel + 3] = Float16(alpha)
            }
            half.withUnsafeBytes {
                texture.replace(region: MTLRegionMake2D(0, row, width, rows), mipmapLevel: 0,
                                withBytes: $0.baseAddress!, bytesPerRow: width * 8)
            }
            row += rows
        }
        return texture
    }

    /// Whether the CPU ever touches a texture, which is the only thing that decides
    /// how it may be stored.
    ///
    /// `.shared` makes a texture CPU-coherent, and on Apple GPUs that forgoes lossless
    /// framebuffer compression. Of the textures the pass graph holds, the CPU touches
    /// exactly two: the input it uploads a photograph into and whichever ping-pong
    /// texture holds the result it reads back. The Scattering Pyramid's levels and
    /// scratch and the MTF Pass's three textures — most of what the Export budget
    /// counts — are written and read only by kernels.
    enum Access {
        /// Uploaded to or read back from, so it has to be visible to both.
        case shared
        /// Only ever a kernel's input or output.
        case deviceOnly
    }

    func makeTexture(width: Int, height: Int, access: Access = .shared) throws -> any MTLTexture {
        guard width > 0, height > 0, width <= 16_384, height <= 16_384 else {
            throw FilmError.invalid("Photo exceeds the supported texture dimensions")
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        // Nothing in `Pipeline.metal` is a render pass; every kernel is a compute
        // kernel writing through `texture2d<half, access::write>`.
        descriptor.usage = access == .shared ? [.shaderRead, .shaderWrite, .renderTarget] : [.shaderRead, .shaderWrite]
        descriptor.storageMode = access == .shared ? .shared : .private
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw FilmError.invalid("Cannot allocate image texture") }
        return texture
    }
}

import UniformTypeIdentifiers
private func UTTypeConformsToRaw(_ identifier: String) -> Bool {
    UTType(identifier)?.conforms(to: .rawImage) == true
}
