import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
import FilmEngine

// Fixtures for the two Export outputs that are pure formatting: the quantised image
// the writer assembles, and the text of an Exported LUT.
//
// Neither is a Golden Image. A Golden Image records what the *render* produces and
// changing one is a deliberate act reviewed through `docs/golden-images.md`. These
// record what happens to a render on its way to a file, which is arithmetic with one
// right answer — so they exist to let that arithmetic be made faster with proof that
// no byte moved, and a change to one of these is a defect rather than a decision.
//
// Set `DYE_RECORD_EXPORT_FIXTURES=1` to write them.

private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/ExportBytes")
private let recording = ProcessInfo.processInfo.environment["DYE_RECORD_EXPORT_FIXTURES"] == "1"

private func check(_ bytes: Data, named name: String) throws {
    let url = fixtures.appendingPathComponent(name)
    if recording {
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        try bytes.write(to: url, options: .atomic)
    }
    let expected = try Data(contentsOf: url)
    guard bytes != expected else { return }
    let offset = zip(bytes, expected).enumerated().first { $0.element.0 != $0.element.1 }?.offset
    let site = offset.map { "first differs at byte \($0) of \(expected.count)" } ?? "lengths differ (\(bytes.count) against \(expected.count))"
    Issue.record("\(name) changed: \(site). Quantisation and formatting have one right answer; this is a defect.")
}

/// A ramp across both axes with a varying alpha, so the writer's premultiply, its
/// clamp and its rounding are all exercised rather than only its copy.
private func ramp(size: Int = 64) throws -> LinearImage {
    var rgba = [Float16](repeating: 0, count: size * size * 4)
    for y in 0..<size {
        for x in 0..<size {
            let index = (y * size + x) * 4
            // Deliberately outside 0...1 at both ends: the clamp is part of the answer.
            rgba[index] = Float16(Double(x) / Double(size - 1) * 1.2 - 0.1)
            rgba[index + 1] = Float16(Double(y) / Double(size - 1))
            rgba[index + 2] = Float16(Double((x + y) % size) / Double(size - 1))
            rgba[index + 3] = Float16(0.25 + 0.75 * Double(y) / Double(size - 1))
        }
    }
    return try LinearImage(width: size, height: size, rgba: rgba)
}

/// The raster a written file decodes back to. What the writer quantised, read through
/// the container rather than around it, so a lossless format is compared whole and a
/// lossy one is compared where its own encoder is deterministic.
private func raster(of data: Data) throws -> Data {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    return try #require(image.dataProvider?.data as Data?)
}

@Test func theWrittenImageIsByteIdenticalForEveryFormat() async throws {
    let renderer = try Renderer()
    let profile = try #require(ProfileCatalogue.bundled().profiles.first { $0.id == "portra-400" })
    let image = try ramp()
    // A fixed date, so the fixture is the pixels rather than the clock.
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let options = ExportOptions(textureBudgetBytes: 32 * 32 * 8 * TilePlan.tileTextureCount,
                                minimumTileEdge: 16, thermalState: .nominal, creationDate: date)
    let plan = try await renderer.tilePlan(image: .linear(image), profile: profile, options: options)
    // Several Tiles, so the fixture covers the seam between what one Tile wrote and
    // what the next one did, not merely the arithmetic inside one.
    #expect(plan.count > 1)
    for format in ExportFormat.allCases {
        for output in [RenderSettings.Output.displayP3, .sRGB] {
            let data = try await renderer.export(image: .linear(image), profile: profile,
                                                 settings: .init(output: output), format: format, options: options)
            // TIFF is lossless and its bytes are ours, so the file itself is the claim.
            // HEIF and JPEG go through a system encoder whose bytes are not, so the
            // claim there is the raster it decodes back to.
            let bytes = format == .tiff ? data : try raster(of: data)
            try check(bytes, named: "portra-400-\(output)-\(format.rawValue).bin")
        }
    }
}

@Test func theExportedLUTTextIsByteIdentical() async throws {
    let renderer = try Renderer()
    let profile = try #require(ProfileCatalogue.bundled().profiles.first { $0.id == "portra-400" })
    let settings = RenderSettings(output: .displayP3, temperatureKelvin: 4800, tint: 12, exposureStops: 0.5,
                                  developmentOffset: 1, halationIntensity: 0, bloomIntensity: 0, grainIntensity: 0)
    let text = try await renderer.exportedLUT(profile: profile, settings: settings)
    try check(Data(text.utf8), named: "portra-400-displayP3.cube")
    // A smaller lattice exercises the same formatter over a different count, and the
    // header lines that carry the Stock and the controls come out the same either way.
    let small = try await renderer.exportedLUT(profile: profile, settings: settings, size: 9)
    try check(Data(small.utf8), named: "portra-400-displayP3-9.cube")
}
