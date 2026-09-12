import CoreGraphics
import CoreImage
import ImageIO
import Metal
import Foundation

/// What the decode path will accept from a file, on both Render Paths.
///
/// Two bounds, because one of them does not do the job on its own. The per-edge
/// bound is a texture limit and cannot be relaxed; on its own it admits a
/// 16384 x 16384 frame, which is 268 megapixels and several gigabytes of transient
/// raster. The total-pixel bound is what closes that, and it is set comfortably
/// above any camera a photograph is likely to come from — a 100 megapixel
/// medium-format back is 11656 x 8742 — so it excludes decompression bombs and
/// nothing anybody actually shot.
public enum ImageLimits {
    /// The largest texture edge the supported devices can allocate.
    public static let maximumEdge = 16_384
    /// 120 megapixels, which no consumer camera reaches.
    public static let maximumPixels = 120_000_000

    /// Checked against the file's header before anything is allocated for pixels,
    /// which is the only place the check protects anyone.
    static func check(width: Int, height: Int) throws {
        guard width > 0, height > 0 else { throw FilmError.invalid("Photo has no usable dimensions") }
        // Both messages name the size and the limit, because a photograph vanishing
        // with nothing said about why is the thing being fixed here.
        guard width <= maximumEdge, height <= maximumEdge else {
            throw FilmError.invalid("This photo is too large: \(width) × \(height), and no edge may exceed \(maximumEdge) pixels")
        }
        guard width * height <= maximumPixels else {
            let megapixels = Int((Double(width * height) / 1e6).rounded())
            throw FilmError.invalid("This photo is too large: \(megapixels) megapixels, and the limit is \(maximumPixels / 1_000_000) megapixels")
        }
    }
}

struct ImageDecoder {
    let device: any MTLDevice
    let workingSpace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
    private let queue: any MTLCommandQueue
    /// Core Image is confined to RAW decoding and the colour-managed handoff.
    private let context: CIContext
    /// How much staging buffer the colour-managed draw may hold at once.
    let bandBytes: Int

    init(device: any MTLDevice, bandBytes: Int = 64 << 20) throws {
        self.device = device
        self.bandBytes = max(bandBytes, 1 << 20)
        guard let queue = device.makeCommandQueue() else { throw FilmError.invalid("Metal is unavailable") }
        self.queue = queue
        context = CIContext(mtlDevice: device, options: [.workingColorSpace: workingSpace, .cacheIntermediates: false])
    }

    /// `maximumDimension` downsamples in the linear Working Space for the Preview Render Path.
    ///
    /// Runs on whatever actor asked for it rather than hopping off one. The decode is
    /// async because the RAW branch awaits the GPU rather than blocking on it, and an
    /// `MTLTexture` is not `Sendable` — so without inheriting the caller's isolation
    /// the texture this returns would be crossing an isolation boundary to get home.
    /// The Renderer is the only caller and the decoder is its own.
    func decode(_ data: Data, maximumDimension: Int? = nil, assumingSRGB: Bool = false,
                isolation: isolated (any Actor)? = #isolation) async throws -> any MTLTexture {
        if let maximumDimension, maximumDimension < 1 { throw FilmError.invalid("Preview dimension must be positive") }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw FilmError.photo(.unsupportedFormat)
        }
        let type = CGImageSourceGetType(source) as String? ?? ""
        let header = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        // Bound the *source* before decoding it. ImageIO parses a header without
        // decoding a pixel, so an oversized frame is refused for the cost of reading
        // a few bytes rather than for the cost of its raster.
        // A file whose header does not state its size cannot be bounded before it is
        // decoded, so it is refused rather than decoded and bounded afterwards — which
        // is the ordering this check exists to remove.
        guard let sourceWidth = header?[kCGImagePropertyPixelWidth] as? Int,
              let sourceHeight = header?[kCGImagePropertyPixelHeight] as? Int else {
            throw FilmError.invalid("This photo does not declare its size")
        }
        try ImageLimits.check(width: sourceWidth, height: sourceHeight)
        if UTTypeConformsToRaw(type) {
            guard let raw = CIRAWFilter(imageData: data, identifierHint: type) else {
                throw FilmError.photo(.unsupportedRaw)
            }
            raw.isDraftModeEnabled = false
            let size = raw.nativeSize
            guard size.width.isFinite, size.height.isFinite, size.width >= 1, size.height >= 1 else {
                throw FilmError.invalid("RAW decode failed")
            }
            try ImageLimits.check(width: Int(size.width), height: Int(size.height))
            let native = max(size.width, size.height)
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
            // `isEmpty` is `width <= 0 || height <= 0` and every comparison against NaN
            // is false, so a NaN extent is neither empty nor infinite and `Int(_:)` on
            // it is a trap rather than a throw. So is `Int(1e300)`. Both are ruled out
            // here rather than at the conversion.
            guard let image = raw.outputImage, !image.extent.isEmpty, !image.extent.isInfinite,
                  image.extent.width.isFinite, image.extent.height.isFinite,
                  image.extent.width >= 1, image.extent.height >= 1 else {
                throw FilmError.invalid("RAW decode failed")
            }
            let texture = try makeTexture(width: Int(image.extent.width), height: Int(image.extent.height))
            // Render on an explicit command buffer and await it: with a nil buffer Core
            // Image commits asynchronously and later reads of the texture race the decode.
            guard let command = queue.makeCommandBuffer() else { throw FilmError.invalid("Cannot create decode command") }
            context.render(image, to: texture, commandBuffer: command, bounds: image.extent, colorSpace: workingSpace)
            try await withCheckedThrowingContinuation(Renderer.completion(command))
            return texture
        }
        // A file the system will not decode and a file with no colour tag are two
        // different failures, and used to share one misleading message.
        guard let image = Self.image(from: source, maximumDimension: maximumDimension),
              let space = image.colorSpace, space.model == .rgb || space.model == .monochrome else {
            throw FilmError.photo(.undecodable)
        }
        let exif = header?[kCGImagePropertyExifDictionary] as? [CFString: Any]
        // `assumingSRGB` is the user having said "open it anyway" to the refusal below,
        // which is the only thing that can establish the assignment the file lacks.
        guard assumingSRGB || header?[kCGImagePropertyProfileName] != nil || exif?[kCGImagePropertyExifColorSpace] as? Int == 1 else {
            // ImageIO supplies a default sRGB CGColorSpace even when the file has
            // no tag. The metadata must establish that assignment explicitly.
            throw FilmError.photo(.untagged)
        }
        let orientation = header?[kCGImagePropertyOrientation] as? Int ?? 1
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
        // For a 48MP Export that is 1.45GB resident before the first Tile is rendered —
        // four times the largest allocation `ImageWriter` reasons about, and accounted
        // for nowhere. The Preview no longer reaches this size at all, because the
        // source is subsampled during decode; the Export still does, and it is the path
        // where the frame is the whole frame by definition.
        //
        // The rows are the *destination's*, so a band is a band of the texture whatever
        // the EXIF orientation did to the axes; the orientation transform composes with
        // a translation that puts the band's rows where the whole-frame draw would have
        // put them. `aBandedDecodeMatchesAWholeFrameDecodeAtEveryOrientation` is the
        // assertion that this is a memory change and not a pixel one.
        let bandRows = max(1, min(height, bandBytes / (width * 16)))
        // A band is drawn one row wider than it keeps at each edge it has a neighbour
        // at, and the margin is thrown away. Core Graphics places a *flipped* draw one
        // pixel across at the rows its own context edges sit on: an untiled decode pays
        // that once, at the frame's edge, and a banded one would pay it once per band,
        // at rows in the middle of the photograph. Keeping only the interior of each
        // band leaves the frame's own edges as the only ones in the result — which is
        // what the untiled decode has.
        var staging = [Float](repeating: 0, count: width * (bandRows + 2) * 4)
        var half = [Float16](repeating: 0, count: width * bandRows * 4)
        var row = 0
        while row < height {
            let rows = min(bandRows, height - row)
            // What is drawn above and below the band's own rows, and so discarded.
            let lead = row > 0 ? 1 : 0
            let drawn = lead + rows + (row + rows < height ? 1 : 0)
            let start = lead * width * 4
            let count = width * rows * 4
            for index in 0..<(width * drawn * 4) { staging[index] = 0 }
            try staging.withUnsafeMutableBytes { bytes in
                guard let context = CGContext(data: bytes.baseAddress, width: width, height: drawn,
                    bitsPerComponent: 32, bytesPerRow: width * 16, space: workingSpace,
                    bitmapInfo: CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue |
                        CGImageAlphaInfo.premultipliedLast.rawValue) else {
                    throw FilmError.invalid("Cannot create colour-managed decode context")
                }
                // Core Graphics counts rows from the bottom and the texture upload from
                // the top, and the whole-frame form relied on that: buffer row 0 is
                // texture row 0. A band's own buffer row 0 is the top of the rows it
                // draws, so what the drawing has to come down by is everything *below*
                // the band rather than everything above it. Shifting by `row` instead
                // cycled the frame: a two-band 12MP Export came out of Photos with its
                // lower band on top, which is what this arithmetic is.
                context.translateBy(x: 0, y: -CGFloat(height - drawn - row + lead))
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
            //
            // `clampedHalf` rather than `Float16(_:)` for every component, including
            // alpha: that is where "pixels are finite" is established rather than
            // assumed, and the divide immediately above is what can break it, since the
            // alpha it divides by can be arbitrarily small.
            for pixel in stride(from: 0, to: count, by: 4) {
                let source = start + pixel
                let alpha = staging[source + 3]
                if alpha > 0 {
                    for channel in 0..<3 { half[pixel + channel] = Self.clampedHalf(staging[source + channel] / alpha) }
                } else {
                    for channel in 0..<3 { half[pixel + channel] = Self.clampedHalf(staging[source + channel]) }
                }
                half[pixel + 3] = Self.clampedHalf(alpha)
            }
            half.withUnsafeBytes {
                texture.replace(region: MTLRegionMake2D(0, row, width, rows), mipmapLevel: 0,
                                withBytes: $0.baseAddress!, bytesPerRow: width * 8)
            }
            row += rows
        }
        return texture
    }

    /// The Preview Render Path asks ImageIO for a thumbnail rather than for the frame,
    /// so ImageIO subsamples *during* decode. Drawing a full-resolution `CGImage` down
    /// would shrink the destination and materialise the source raster anyway, which is
    /// what made the Preview cost the photograph rather than the Preview.
    private static func image(from source: CGImageSource, maximumDimension: Int?) -> CGImage? {
        guard let maximumDimension else { return CGImageSourceCreateImageAtIndex(source, 0, nil) }
        // Orientation is applied by the drawing transform below, from the metadata, so
        // ImageIO must not also apply it here.
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                                        kCGImageSourceCreateThumbnailWithTransform: false,
                                        kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// NaN to zero, and a magnitude past float16 range to the largest it can hold.
    private static func clampedHalf(_ value: Float) -> Float16 {
        guard value.isFinite else { return value.isNaN ? 0 : (value > 0 ? .greatestFiniteMagnitude : -.greatestFiniteMagnitude) }
        return Float16(min(max(value, -Float(Float16.greatestFiniteMagnitude)), Float(Float16.greatestFiniteMagnitude)))
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
        try ImageLimits.check(width: width, height: height)
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
