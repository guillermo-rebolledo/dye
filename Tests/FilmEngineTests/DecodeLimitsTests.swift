import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import os
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
    #expect(bomb.count < 1_500_000)
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

@Test func aGenuine48MegapixelPhotographIsWellInsideTheLimit() async throws {
    // 8000 × 6000 is what a current phone writes. The bound has to protect the user
    // without excluding the user's own files, so this is the other half of the bomb.
    let data = try fixture("large-photograph.png")
    let renderer = try Renderer()
    #expect(throws: Never.self) { try ImageLimits.check(width: 8000, height: 6000) }
    let preview = try await renderer.decode(data, maximumDimension: 2048)
    #expect(max(preview.width, preview.height) == 2048)
    #expect(preview.width == 2048 && preview.height == 1536)
}

@Test func aDecodedPhotographExportsAndStillMatchesItsUntiledRender() async throws {
    // The guards must not change a legitimate render. Same claim as
    // `aTiledExportReproducesTheUntiledRenderOfTheSameFrame`, made of a photograph
    // that arrived as a file and went through the whole decode path to get here.
    let renderer = try Renderer()
    let data = try photograph(width: 600, height: 450)
    let profile = try #require(ProfileCatalogue.bundled().profiles.first { $0.id == "portra-400" })
    let settings = RenderSettings(output: .displayP3, grainIntensity: 0)
    let decoded = try await renderer.decode(data)
    #expect(decoded.width == 600 && decoded.height == 450)
    let whole = try await renderer.render(image: .linear(decoded), profile: profile, settings: settings)
    let options = ExportOptions(textureBudgetBytes: 128 * 128 * 8 * 14, minimumTileEdge: 16, thermalState: .nominal)
    let plan = try await renderer.tilePlan(image: .encoded(data), profile: profile, settings: settings, options: options)
    #expect(plan.count > 1)
    let tiled = try await renderer.exportedPixels(image: .encoded(data), profile: profile,
                                                  settings: settings, options: options)
    #expect(tiled.width == whole.width && tiled.height == whole.height)
    for index in 0..<(whole.width * whole.height * 4) {
        #expect(abs(Double(tiled.rgba[index]) - Double(whole.rgba[index])) < 0.01)
    }
    // And it still writes a file of the size it decoded.
    let exported = try await renderer.export(image: .encoded(data), profile: profile,
                                             settings: settings, format: .jpeg, options: options)
    let source = try #require(CGImageSourceCreateWithData(exported as CFData, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    #expect(properties[kCGImagePropertyPixelWidth] as? Int == 600)
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
    // The invariant `ImageWriter` stands behind: nothing non-finite reaches the point
    // where a quantisation would trap. Asserted across both decode branches — the RAW
    // one through Core Image, and the colour-managed one through Core Graphics, whose
    // unpremultiply divides by an alpha that can be arbitrarily small.
    let renderer = try Renderer()
    for name in ["linear-high.dng", "linear-low.dng", "large-photograph.png"] {
        let image = try await renderer.decode(try fixture(name), maximumDimension: 256)
        #expect(image.rgba.allSatisfy { $0.isFinite }, "\(name)")
    }
    let image = try await renderer.decode(try photograph(width: 64, height: 64))
    #expect(image.rgba.allSatisfy { $0.isFinite })
}

/// The process's physical footprint right now, which is what jetsam reads.
private func physicalFootprint() -> Int {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
}

/// Opt-in, and it must be run **alone**: the number it reads belongs to the whole
/// process, and Swift Testing runs everything else concurrently with it, so a
/// screen-sized render in another test lands in this one's measurement.
///
///     DYE_MEMORY_PROBE=1 swift test --filter previewDecodePeakIsBounded
///
/// The deterministic half of the same claim — that the Preview comes out at the
/// Preview's size and matches a full decode of the same frame — is asserted
/// unconditionally above and does gate CI.
@Test(.enabled(if: ProcessInfo.processInfo.environment["DYE_MEMORY_PROBE"] == "1"), .serialized)
func previewDecodePeakIsBoundedByThePreviewAndNotBySourceDimensions() async throws {
    let data = try fixture("large-photograph.png")
    let renderer = try Renderer()
    _ = try await renderer.decode(data, maximumDimension: 64)
    let baseline = physicalFootprint()
    let peak = OSAllocatedUnfairLock(initialState: baseline)
    let sampling = Task.detached(priority: .high) {
        while !Task.isCancelled {
            let now = physicalFootprint()
            peak.withLock { $0 = max($0, now) }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
    _ = try await renderer.decode(data, maximumDimension: 2048)
    sampling.cancel()
    let growth = peak.withLock { $0 } - baseline
    // The 2048-pixel Preview costs about 100MB of its own — one float buffer, one
    // float16 buffer and the texture — and that is the floor. Decoding whole and
    // scaling down materialises 8000 × 6000 of source raster on top of it, which
    // measures at 280MB against the 114MB this path pays.
    #expect(growth < 160 << 20, "grew \(growth >> 20)MB decoding a 48 megapixel source at 2048")
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
