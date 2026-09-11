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

    init(device: any MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else { throw FilmError.invalid("Metal is unavailable") }
        self.queue = queue
        context = CIContext(mtlDevice: device, options: [.workingColorSpace: workingSpace, .cacheIntermediates: false])
    }

    /// `maximumDimension` downsamples in the linear Working Space for the Preview Render Path.
    func decode(_ data: Data, maximumDimension: Int? = nil) throws -> any MTLTexture {
        if let maximumDimension, maximumDimension < 1 { throw FilmError.invalid("Preview dimension must be positive") }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw FilmError.invalid("Unsupported photo file")
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
                throw FilmError.invalid("The system RAW decoder does not support this photo")
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
            // Render on an explicit command buffer and wait: with a nil buffer Core Image
            // commits asynchronously and later reads of the texture race the decode.
            guard let command = queue.makeCommandBuffer() else { throw FilmError.invalid("Cannot create decode command") }
            context.render(image, to: texture, commandBuffer: command, bounds: image.extent, colorSpace: workingSpace)
            command.commit()
            command.waitUntilCompleted()
            if let error = command.error { throw error }
            return texture
        }
        guard let image = Self.image(from: source, maximumDimension: maximumDimension),
              let space = image.colorSpace, space.model == .rgb || space.model == .monochrome else {
            throw FilmError.invalid("Photo has no supported input colour profile")
        }
        let exif = header?[kCGImagePropertyExifDictionary] as? [CFString: Any]
        guard header?[kCGImagePropertyProfileName] != nil || exif?[kCGImagePropertyExifColorSpace] as? Int == 1 else {
            // ImageIO supplies a default sRGB CGColorSpace even when the file has
            // no tag. The metadata must establish that assignment explicitly.
            throw FilmError.invalid("This photo has no colour profile; assign one before opening it")
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
        // The invariant the writer downstream relies on. `Float16(_: Float)` rounds an
        // out-of-range magnitude to infinity rather than trapping, and the
        // unpremultiply above divides by an alpha that can be arbitrarily small, so
        // this is where "pixels are finite" is established rather than assumed.
        let half = pixels.map(Self.clampedHalf)
        half.withUnsafeBytes {
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                            withBytes: $0.baseAddress!, bytesPerRow: width * 8)
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

    func makeTexture(width: Int, height: Int) throws -> any MTLTexture {
        try ImageLimits.check(width: width, height: height)
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
