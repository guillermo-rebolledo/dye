import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Assembles the cores of rendered Tiles into one colour-managed file.
///
/// The renderer delivers float16 already encoded for the requested Output, so the
/// writer's only jobs are to quantise, to premultiply — Core Graphics has no
/// straight-alpha 16-bit format — and to tag the result with the colour space the
/// Output Transform actually produced. Tagging is not cosmetic: an untagged file is
/// read as sRGB, which would silently undo a Display P3 export.
///
/// Holding the assembled frame is the Export path's largest allocation: 183MB for a
/// 48MP eight-bit frame against the 380MB *per intermediate texture* an untiled
/// render would need, and it is written once and read once rather than ping-ponged.
final class ImageWriter {
    let format: ExportFormat
    let output: RenderSettings.Output
    let width: Int
    let height: Int
    private var pixels: Data
    private var bytesPerComponent: Int { format.bitsPerComponent / 8 }
    private var bytesPerRow: Int { width * 4 * bytesPerComponent }

    init(format: ExportFormat, output: RenderSettings.Output, width: Int, height: Int) throws {
        guard output != .workingSpace else {
            throw FilmError.invalid("The Working Space is not a deliverable; export Display P3 or sRGB")
        }
        guard width > 0, height > 0 else { throw FilmError.invalid("Invalid export dimensions") }
        self.format = format
        self.output = output
        self.width = width
        self.height = height
        pixels = Data(count: width * height * 4 * (format.bitsPerComponent / 8))
        guard pixels.count == width * height * 4 * bytesPerComponent else {
            throw FilmError.invalid("Cannot allocate the export image")
        }
    }

    /// Copies one Tile's core into the frame. `rgba` is the core alone, row-major.
    func write(_ rgba: UnsafeBufferPointer<Float16>, x: Int, y: Int, width tileWidth: Int, height tileHeight: Int) {
        precondition(rgba.count == tileWidth * tileHeight * 4)
        precondition(x >= 0 && y >= 0 && x + tileWidth <= width && y + tileHeight <= height)
        let maximum = Double((1 << format.bitsPerComponent) - 1)
        let eightBit = format.bitsPerComponent == 8
        pixels.withUnsafeMutableBytes { raw in
            for row in 0..<tileHeight {
                let source = row * tileWidth * 4
                let destination = ((y + row) * width + x) * 4
                for column in 0..<tileWidth {
                    // Straight alpha in, premultiplied out, because Core Graphics has
                    // no straight-alpha 16-bit format. Alpha itself is not multiplied.
                    let alpha = Self.clamped(Double(rgba[source + column * 4 + 3]))
                    for channel in 0..<4 {
                        let value = Double(rgba[source + column * 4 + channel]) * (channel == 3 ? 1 : alpha)
                        let quantised = (Self.clamped(value) * maximum).rounded()
                        let index = destination + column * 4 + channel
                        if eightBit {
                            raw.storeBytes(of: UInt8(quantised), toByteOffset: index, as: UInt8.self)
                        } else {
                            raw.storeBytes(of: UInt16(quantised).littleEndian, toByteOffset: index * 2, as: UInt16.self)
                        }
                    }
                }
            }
        }
    }

    /// Swift's `min`/`max` are not NaN-clamping — `max(.nan, 0)` is `.nan` — and
    /// `UInt8(Double.nan)` is a hard trap rather than a throwable error, so it could
    /// not be caught by the Export's own `catch`. Decode establishes that pixels are
    /// finite; this is the last line of defence behind that, and it costs one branch.
    private static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return value > 0 ? 1 : 0 }
        return min(max(value, 0), 1)
    }

    func encode(quality: Double, creationDate: Date? = nil) throws -> Data {
        let space = output == .sRGB ? CGColorSpace(name: CGColorSpace.sRGB) : CGColorSpace(name: CGColorSpace.displayP3)
        var info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        if format.bitsPerComponent == 16 { info.insert(.byteOrder16Little) }
        guard let space, let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: format.bitsPerComponent,
                                  bitsPerPixel: format.bitsPerComponent * 4, bytesPerRow: bytesPerRow,
                                  space: space, bitmapInfo: info, provider: provider, decode: nil,
                                  shouldInterpolate: false, intent: .defaultIntent) else {
            throw FilmError.invalid("Cannot assemble the exported image")
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.contentType.identifier as CFString, 1, nil) else {
            throw FilmError.invalid("This device cannot write \(format.displayName)")
        }
        var properties: [CFString: Any] = creationDate.map { ExportDate.properties(for: $0) } ?? [:]
        if format.isLossy { properties[kCGImageDestinationLossyCompressionQuality] = min(max(quality, 0), 1) }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FilmError.invalid("Encoding the export failed") }
        return data as Data
    }
}
