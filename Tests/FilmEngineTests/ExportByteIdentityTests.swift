import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
import FilmEngine

// Fixtures for the two Export outputs that are pure formatting: the pixels the writer
// quantises, and the text of an Exported LUT.
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
private func ramp(size: Int = 64, opaque: Bool = false) throws -> LinearImage {
    var rgba = [Float16](repeating: 0, count: size * size * 4)
    for y in 0..<size {
        for x in 0..<size {
            let index = (y * size + x) * 4
            // Deliberately outside 0...1 at both ends: the clamp is part of the answer.
            rgba[index] = Float16(Double(x) / Double(size - 1) * 1.2 - 0.1)
            rgba[index + 1] = Float16(Double(y) / Double(size - 1))
            rgba[index + 2] = Float16(Double((x + y) % size) / Double(size - 1))
            rgba[index + 3] = opaque ? 1 : Float16(0.25 + 0.75 * Double(y) / Double(size - 1))
        }
    }
    return try LinearImage(width: size, height: size, rgba: rgba)
}

/// The pixels a written file decodes back to, with any row padding removed.
///
/// The file itself is the wrong thing to record. A 16-bit TIFF is lossless and its
/// pixels are exactly what the writer quantised, but the container around them carries
/// an embedded ICC profile that differs between OS versions — which is how the first
/// version of this fixture passed here and failed on CI, 452 bytes from the end, inside
/// the profile. And `bytesPerRow` may be padded for alignment, which is the platform's
/// business rather than the writer's.
private func pixels(of data: Data) throws -> Data {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let raster = try #require(image.dataProvider?.data as Data?)
    let used = image.width * image.bitsPerPixel / 8
    var pixels = Data(capacity: used * image.height)
    for row in 0..<image.height {
        let start = row * image.bytesPerRow
        pixels.append(raster[start..<(start + used)])
    }
    return pixels
}

@Test func theWrittenImageIsByteIdenticalForTheFormatThatCarriesItLosslessly() async throws {
    // TIFF is the only container whose pixels survive it, so it is the only one whose
    // pixels can be recorded. HEIF and JPEG go through a system encoder: what they
    // decode back to is that encoder's arithmetic rather than the writer's, and it
    // moves between OS versions. `writersProduceTaggedFilesInEveryFormat` is what
    // covers those, and the 8-bit quantisation has its own assertion below.
    let renderer = try Renderer()
    let profile = try #require(ProfileCatalogue.bundled().profiles.first { $0.id == "portra-400" })
    let image = try ramp()
    let options = ExportOptions(textureBudgetBytes: 32 * 32 * 8 * TilePlan.tileTextureCount,
                                minimumTileEdge: 16, thermalState: .nominal,
                                creationDate: Date(timeIntervalSince1970: 1_700_000_000))
    let plan = try await renderer.tilePlan(image: .linear(image), profile: profile, options: options)
    // Several Tiles, so the fixture covers the seam between what one Tile wrote and
    // what the next one did, not merely the arithmetic inside one.
    #expect(plan.count > 1)
    for output in [RenderSettings.Output.displayP3, .sRGB] {
        let data = try await renderer.export(image: .linear(image), profile: profile,
                                             settings: .init(output: output), format: .tiff, options: options)
        try check(try pixels(of: data), named: "portra-400-\(output)-tiff.raster")
    }
}

@Test func theEightBitQuantisationAgreesWithTheSixteenBitOne() async throws {
    // The 8-bit path is never observable losslessly — both containers that use it are
    // lossy — so it cannot have a fixture of its own. What it can have is agreement
    // with the path that does: the two differ only in what they scale by and what they
    // convert to, so a rounding rule that moved in one and not the other shows up here
    // as a bias no lossy encoder would introduce.
    let renderer = try Renderer()
    let profile = try #require(ProfileCatalogue.bundled().profiles.first { $0.id == "portra-400" })
    // Opaque, because JPEG cannot carry alpha: ImageIO composites a premultiplied
    // image over white on the way in, so a translucent ramp would have the two
    // containers disagreeing about the background rather than about the quantisation.
    // The premultiply itself is covered by the fixture above, which is not opaque.
    let image = try ramp(opaque: true)
    let options = ExportOptions(textureBudgetBytes: 32 * 32 * 8 * TilePlan.tileTextureCount,
                                minimumTileEdge: 16, thermalState: .nominal, quality: 1)
    let settings = RenderSettings(output: .displayP3)
    let wide = try await renderer.export(image: .linear(image), profile: profile, settings: settings,
                                         format: .tiff, options: options)
    let narrow = try await renderer.export(image: .linear(image), profile: profile, settings: settings,
                                           format: .jpeg, options: options)
    let sixteen = try pixels(of: wide), eight = try pixels(of: narrow)
    #expect(sixteen.count == eight.count * 2)
    var worst = 0, total = 0, counted = 0
    for index in 0..<eight.count {
        // Colour only: both are opaque here, so the alpha channel says nothing.
        guard index % 4 != 3 else { continue }
        // Little-endian 16-bit, and the same value at 8 bits is it over 257.
        let value = Int(sixteen[index * 2]) | Int(sixteen[index * 2 + 1]) << 8
        let difference = abs(Int(eight[index]) - Int((Double(value) / 257).rounded()))
        worst = max(worst, difference)
        total += difference
        counted += 1
    }
    let mean = Double(total) / Double(counted)
    // A lossy encoder at full quality moves a code value or two; a quantisation rule
    // that changed would move every one of them the same way.
    #expect(worst <= 6, "worst component differs by \(worst)")
    #expect(mean < 1, "mean component differs by \(mean)")
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
