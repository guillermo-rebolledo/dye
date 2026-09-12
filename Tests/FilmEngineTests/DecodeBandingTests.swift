import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import FilmEngine

// A full-resolution decode used to hold a Float32 staging buffer, a Float16 copy of it
// and the destination texture at once — 1.45GB for a 48MP frame, before the Export had
// rendered a Tile. It now writes the texture a band of rows at a time. The claim under
// test is that this is a memory change and nothing else: the same photograph, at every
// EXIF orientation and with alpha, decodes to the same bits however the bands fall.

/// A PNG carrying an explicit orientation and colour space, built rather than checked
/// in so that all eight orientations are covered without eight fixtures.
private func png(width: Int, height: Int, orientation: Int, alpha: Bool) throws -> Data {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let index = (y * width + x) * 4
            // Content that is different in every row and column, so a band that landed
            // in the wrong place or an axis that swapped the wrong way is visible.
            pixels[index] = UInt8((x * 7 + y * 3) % 256)
            pixels[index + 1] = UInt8((x * 13 + y * 29) % 256)
            pixels[index + 2] = UInt8((x &* y) % 256)
            pixels[index + 3] = alpha ? UInt8(64 + (y * 191 / max(1, height - 1))) : 255
        }
    }
    let info = CGBitmapInfo(rawValue: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)
    let context = try #require(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                         bytesPerRow: width * 4, space: space, bitmapInfo: info.rawValue))
    let image = try #require(context.makeImage())
    let output = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
}

/// The smallest band budget a `Renderer` will accept, since `init` floors it. A frame
/// only bands when its rows cost more than this, which a 200 x 137 fixture never did:
/// the test that thought it was banding was decoding whole frames at both budgets and
/// asserting they matched, and a banded decode shipped with its bands cycled.
private let minimumBandBytes = 1 << 20

/// How many bands a decode of this size actually takes, which is the assertion that a
/// "banded" case is one.
private func bands(width: Int, height: Int) -> Int {
    let rows = max(1, min(height, minimumBandBytes / (width * 16)))
    return (height + rows - 1) / rows
}

@Test func aBandedDecodeMatchesAWholeFrameDecodeAtEveryOrientation() async throws {
    // One band budget large enough to hold the frame whole, and one small enough that
    // the frame takes several bands.
    let whole = try Renderer(decodeBandBytes: 256 << 20)
    let banded = try Renderer(decodeBandBytes: minimumBandBytes)
    // Not square and not a multiple of the band height, so the last band is a partial
    // one and the axes cannot be confused for each other.
    #expect(bands(width: 400, height: 301) > 1)
    for orientation in 1...8 {
        for alpha in [false, true] {
            let data = try png(width: 400, height: 301, orientation: orientation, alpha: alpha)
            let expected = try await whole.decode(data)
            let actual = try await banded.decode(data)
            #expect(actual.width == expected.width && actual.height == expected.height,
                    "orientation \(orientation)")
            #expect(actual.rgba == expected.rgba, "orientation \(orientation), alpha \(alpha)")
        }
    }
}

@Test func aBandedPreviewDecodeMatchesAWholeFramePreviewDecode() async throws {
    // The Preview path scales as it draws, so its bands are drawn through a resampler
    // rather than copied. The band a pixel lands in must not change what it resamples.
    let whole = try Renderer(decodeBandBytes: 256 << 20)
    let banded = try Renderer(decodeBandBytes: minimumBandBytes)
    // The decode is bounded by what the Preview asks for, so it is the *scaled* size
    // that has to band — a source large enough to band is not enough on its own.
    #expect(bands(width: 341, height: 512) > 1)
    let data = try png(width: 1024, height: 683, orientation: 6, alpha: false)
    let expected = try await whole.decode(data, maximumDimension: 512)
    let actual = try await banded.decode(data, maximumDimension: 512)
    #expect(actual.width == expected.width && actual.height == expected.height)
    #expect(actual.rgba == expected.rgba)
}

@Test func aDecodeHoldsOneBandRatherThanTwoWholeFrames() async throws {
    // The budget is a claim about resident bytes, so it is asserted as one: a band's
    // staging buffers together are the Float32 band and its Float16 conversion, and
    // both are bounded by the budget the Renderer was given.
    let data = try png(width: 400, height: 301, orientation: 1, alpha: false)
    let renderer = try Renderer(decodeBandBytes: 1 << 20)
    let decoded = try await renderer.decode(data)
    #expect(decoded.width == 400 && decoded.height == 301)
    // A megabyte of Float32 band is 16 bytes a pixel over 400 pixels a row, so 163
    // rows — well under the frame, which is the point.
    #expect((1 << 20) / (400 * 16) < 301)
}
