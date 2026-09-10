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

    init(device: any MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else { throw FilmError.invalid("Metal is unavailable") }
        self.queue = queue
        context = CIContext(mtlDevice: device, options: [.workingColorSpace: workingSpace, .cacheIntermediates: false])
    }

    /// `maximumDimension` downsamples in the linear Working Space for the Preview Render Path.
    func decode(_ data: Data, maximumDimension: Int? = nil, assumingSRGB: Bool = false) throws -> any MTLTexture {
        if let maximumDimension, maximumDimension < 1 { throw FilmError.invalid("Preview dimension must be positive") }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw FilmError.photo(.unsupportedFormat)
        }
        let type = CGImageSourceGetType(source) as String? ?? ""
        if UTTypeConformsToRaw(type) {
            guard let raw = CIRAWFilter(imageData: data, identifierHint: type) else {
                throw FilmError.photo(.unsupportedRaw)
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
            // Render on an explicit command buffer and wait: with a nil buffer Core Image
            // commits asynchronously and later reads of the texture race the decode.
            guard let command = queue.makeCommandBuffer() else { throw FilmError.invalid("Cannot create decode command") }
            context.render(image, to: texture, commandBuffer: command, bounds: image.extent, colorSpace: workingSpace)
            command.commit()
            command.waitUntilCompleted()
            if let error = command.error { throw error }
            return texture
        }
        // A file the system will not decode and a file with no colour tag are two
        // different failures, and used to share one misleading message.
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = image.colorSpace, space.model == .rgb || space.model == .monochrome else {
            throw FilmError.photo(.undecodable)
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let exif = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any]
        guard assumingSRGB || properties?[kCGImagePropertyProfileName] != nil || exif?[kCGImagePropertyExifColorSpace] as? Int == 1 else {
            // ImageIO supplies a default sRGB CGColorSpace even when the file has
            // no tag. The metadata must establish that assignment explicitly.
            throw FilmError.photo(.untagged)
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
        var pixels = [Float](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 32, bytesPerRow: width * 16, space: workingSpace,
                bitmapInfo: CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue |
                    CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw FilmError.invalid("Cannot create colour-managed decode context")
            }
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
        // CGContext is premultiplied; the Metal pipeline uses straight alpha.
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 0 {
            for c in 0..<3 { pixels[i + c] /= pixels[i + 3] }
        }
        let half = pixels.map(Float16.init)
        half.withUnsafeBytes {
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                            withBytes: $0.baseAddress!, bytesPerRow: width * 8)
        }
        return texture
    }

    func makeTexture(width: Int, height: Int) throws -> any MTLTexture {
        guard width > 0, height > 0, width <= 16_384, height <= 16_384 else {
            throw FilmError.photo(.tooLarge)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw FilmError.invalid("Cannot allocate image texture") }
        return texture
    }
}

import UniformTypeIdentifiers
private func UTTypeConformsToRaw(_ identifier: String) -> Bool {
    UTType(identifier)?.conforms(to: .rawImage) == true
}
