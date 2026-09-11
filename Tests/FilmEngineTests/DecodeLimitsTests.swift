import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import FilmEngine

// What the decode path will accept from a file, asserted through the renderer seam.
// Photo bytes are the one input an attacker can influence, so the claim under test is
// that an oversized frame is an error message rather than a dead process, and that
// the rejection happens from the header — before anything is allocated for pixels.

private func fixture(_ name: String) throws -> Data {
    let directory = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    return try Data(contentsOf: directory.appendingPathComponent(name))
}

/// A tagged photograph of a given size, encoded as a real file the way a camera
/// writes one. Display P3 because an untagged file is refused before any of this.
private func photograph(width: Int, height: Int, format: UTType = .jpeg) throws -> Data {
    let space = try #require(CGColorSpace(name: CGColorSpace.displayP3))
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                         bytesPerRow: 0, space: space,
                                         bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let encoded = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(encoded, format.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 1] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return encoded as Data
}

@Test func theTotalPixelLimitSitsAboveAnyCameraAndBelowTheEdgeLimitsWorstCase() throws {
    // A 48MP phone, a 61MP full frame and a 100MP medium-format back all pass.
    for (width, height) in [(8064, 6048), (9504, 6336), (11656, 8742)] {
        #expect(throws: Never.self) { try ImageLimits.check(width: width, height: height) }
    }
    // The per-edge limit on its own admits 268 megapixels, which is the hole.
    #expect(throws: FilmError.self) { try ImageLimits.check(width: 16_384, height: 16_384) }
    #expect(throws: FilmError.self) { try ImageLimits.check(width: 16_385, height: 1) }
    #expect(throws: FilmError.self) { try ImageLimits.check(width: 0, height: 100) }
}

@Test func aDecompressionBombIsRejectedFromBothRenderPathsWithAMessageNamingTheLimit() async throws {
    let bomb = try fixture("decompression-bomb.png")
    // A few hundred kilobytes standing for 268 megapixels: the file looks harmless in
    // Messages and costs a gigabyte of raster the moment anything decodes it whole.
    #expect(bomb.count < 1_000_000)
    let renderer = try Renderer()
    for path in ["decode", "preview decode", "export"] {
        let error = await #expect(throws: FilmError.self) {
            switch path {
            case "decode": _ = try await renderer.decode(bomb)
            case "preview decode": _ = try await renderer.decode(bomb, maximumDimension: 2048)
            default: _ = try await renderer.export(image: .encoded(bomb), profile: .identity,
                                                   settings: .init(output: .displayP3))
            }
        }
        // The user is told the photograph is too large, not left watching the app go.
        let message = try #require(error?.localizedDescription)
        #expect(message.contains("268") && message.contains("120"), "\(path): \(message)")
    }
}

@Test func aLegitimatePhotographStillDecodesAndExports() async throws {
    let renderer = try Renderer()
    let data = try photograph(width: 1200, height: 900)
    let full = try await renderer.decode(data)
    #expect(full.width == 1200 && full.height == 900)
    let exported = try await renderer.export(image: .encoded(data), profile: .identity,
                                             settings: .init(output: .displayP3), format: .jpeg)
    let source = try #require(CGImageSourceCreateWithData(exported as CFData, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    #expect(properties[kCGImagePropertyPixelWidth] as? Int == 1200)
}

@Test func previewDecodeIsBoundedByThePreviewRatherThanBySourceDimensions() async throws {
    let renderer = try Renderer()
    let data = try photograph(width: 1600, height: 1200)
    let preview = try await renderer.decode(data, maximumDimension: 512)
    #expect(max(preview.width, preview.height) == 512)
    #expect(abs(Double(preview.width) / Double(preview.height) - 4.0 / 3.0) < 0.02)
    // Subsampling during decode must not change what the Preview shows.
    let full = try await renderer.decode(data)
    let previewCentre = (preview.height / 2 * preview.width + preview.width / 2) * 4
    let fullCentre = (full.height / 2 * full.width + full.width / 2) * 4
    for channel in 0..<3 {
        #expect(abs(Float(preview.rgba[previewCentre + channel]) - Float(full.rgba[fullCentre + channel])) < 0.01)
    }
}

@Test func everyPixelThatLeavesDecodeIsFinite() async throws {
    let renderer = try Renderer()
    for name in ["untagged.png", "linear-high.dng"] {
        guard let data = try? fixture(name), let image = try? await renderer.decode(data) else { continue }
        #expect(image.rgba.allSatisfy { $0.isFinite })
    }
    let image = try await renderer.decode(try photograph(width: 64, height: 64))
    #expect(image.rgba.allSatisfy { $0.isFinite })
}

@Test func nonFinitePixelsAreQuantisedRatherThanTrappingTheWriter() throws {
    // The writer is the last line of defence, and Swift's min/max do not clamp NaN:
    // max(.nan, 0) is .nan and UInt8(.nan) is a trap rather than a throw.
    for format in ExportFormat.allCases {
        let writer = try ImageWriter(format: format, output: .displayP3, width: 2, height: 1)
        let pixels: [Float16] = [.nan, .infinity, -.infinity, .nan, 1, 1, 1, 1]
        pixels.withUnsafeBufferPointer { writer.write($0, x: 0, y: 0, width: 2, height: 1) }
        let data = try writer.encode(quality: 1)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceCreateImageAtIndex(source, 0, nil) != nil)
    }
}
