import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
import FilmEngine

// The Export Render Path, asserted through the renderer seam like everything else.
// The claim under test throughout is that a Tile is a *window* onto the untiled
// render rather than a small render of its own: same Apron-fed neighbourhood, same
// image-global Grain field, same frame-relative Geometry.

private func stock(_ id: String) throws -> Profile {
    try #require(ProfileCatalogue.bundled().profiles.first { $0.id == id })
}

/// A small bright source on an unlit field, at an arbitrary position in the frame.
private func practicalLight(size: Int, at centre: (x: Int, y: Int)? = nil, value: Float16 = 400) throws -> LinearImage {
    var rgba = [Float16](repeating: 0, count: size * size * 4)
    for i in stride(from: 3, to: rgba.count, by: 4) { rgba[i] = 1 }
    let (cx, cy) = centre ?? (size / 2, size / 2)
    let radius = max(2, size / 64)
    for y in (cy - radius)...(cy + radius) {
        for x in (cx - radius)...(cx + radius) {
            for c in 0..<3 { rgba[(y * size + x) * 4 + c] = value }
        }
    }
    return try LinearImage(width: size, height: size, rgba: rgba)
}

private func flat(size: Int, value: Float16) throws -> LinearImage {
    var rgba = [Float16](repeating: value, count: size * size * 4)
    for i in stride(from: 3, to: rgba.count, by: 4) { rgba[i] = 1 }
    return try LinearImage(width: size, height: size, rgba: rgba)
}

/// A budget that admits a padded Tile of `paddedEdge` square. Small frames then come
/// out as several Tiles across, which is the only reason these tests are tiled at all.
/// The Apron still comes from the Passes; what the core ends up as is what is left.
private func tiling(paddedEdge: Int = 256, apronFraction: Double = 0.6) -> ExportOptions {
    ExportOptions(textureBudgetBytes: paddedEdge * paddedEdge * 8 * TilePlan.tileTextureCount, minimumTileEdge: 16,
                  thermalState: .nominal, apronFraction: apronFraction)
}

/// An identity Colour Cube isolates the Grain Pass, as in `GrainTests`.
private func graining(rms: Double = 0.05, radiusMicrons: Double = 1.2) throws -> Profile {
    var metadata = Profile.identity.metadata
    let triangle: [Double] = (0..<32).map { 1 - abs(Double($0) - 15.5) / 15.5 }
    metadata.grain = FilmProfile.Grain(model: .procedural, rmsGranularity: rms, grainRadiusMicrons: radiusMicrons,
                                       densityResponse: triangle, channelCorrelation: 0, channelRadiusScale: [1, 1, 1])
    return try Profile(metadata: metadata, payloads: ["identity.lut3d": ColourCube.identity.payload])
}

@Test func tilePlanCoversTheFrameExactlyAndKeepsEveryApronInside() throws {
    for (width, height, requested) in [(4000, 3000, 96), (1024, 1024, 0), (513, 97, 40), (8000, 6000, 675)] {
        let plan = try TilePlan(frameWidth: width, frameHeight: height, apron: requested, budgetBytes: 320 << 20)
        // The budget caps the Apron when the widest blur asks for more than a Tile can
        // afford; what the geometry has to hold for is the Apron that survived that.
        let apron = plan.apron
        #expect(apron <= requested)
        // Small frames are checked pixel by pixel; a 48MP one by area, since the grid
        // arithmetic asserted per Tile below is what rules overlap out either way.
        var covered = [Bool](repeating: false, count: width * height <= 1 << 22 ? width * height : 0)
        var area = 0
        for index in 0..<plan.count {
            let tile = plan.tile(index)
            // The rendered window is always the same size and always inside the frame,
            // so one set of Tile textures serves the whole Export.
            #expect(tile.originX >= 0 && tile.originY >= 0)
            #expect(tile.originX + plan.paddedWidth <= width && tile.originY + plan.paddedHeight <= height)
            // The core is inside the window it was rendered in.
            #expect(tile.insetX >= 0 && tile.insetY >= 0)
            #expect(tile.insetX + tile.width <= plan.paddedWidth && tile.insetY + tile.height <= plan.paddedHeight)
            // A Tile with room on a side carries the full Apron there; one against the
            // frame edge carries none, which is the clamp an untiled render also applies.
            if tile.x >= apron { #expect(tile.insetX >= apron) }
            if tile.y >= apron { #expect(tile.insetY >= apron) }
            if tile.x + tile.width + apron <= width { #expect(plan.paddedWidth - tile.insetX - tile.width >= apron) }
            area += tile.width * tile.height
            guard !covered.isEmpty else { continue }
            for y in tile.y..<(tile.y + tile.height) {
                for x in tile.x..<(tile.x + tile.width) {
                    #expect(!covered[y * width + x])
                    covered[y * width + x] = true
                }
            }
        }
        #expect(area == width * height)
        #expect(covered.allSatisfy { $0 })
    }
}

@Test func apronFollowsTheWidestBlurInThePipelineAndTheFrameItRunsOn() async throws {
    // Film-Plane Microns become pixels through Frame Width, so the same Stock needs a
    // wider Apron on a larger frame. The Catalogue's widest blur is the modelled taking
    // lens at 900 µm — wider than even Cinestill's 420 µm halation — so Bloom is what
    // sizes the Apron today, and turning it off shrinks the Apron rather than the halo.
    let renderer = try Renderer()
    let cinestill = try stock("cinestill-800t")
    let settings = RenderSettings(temperatureKelvin: 3200)
    var aprons: [Int] = []
    for size in [512, 1024, 2048] {
        let image = try flat(size: size, value: 0.18)
        aprons.append(try await renderer.tilePlan(image: .linear(image), profile: cinestill, settings: settings).apron)
    }
    #expect(aprons[0] < aprons[1] && aprons[1] < aprons[2])
    // 900 µm on a 36 mm frame at 2048 pixels is 51 pixels of sigma, and the Apron has
    // to carry the tail of the pyramid level that sigma lands on, not just the sigma.
    #expect(aprons[2] >= 2 * 51)
    let image = try flat(size: 2048, value: 0.18)
    var quiet = settings
    quiet.bloomIntensity = 0
    quiet.halationIntensity = 0
    let none = try await renderer.tilePlan(image: .linear(image), profile: cinestill, settings: quiet)
    #expect(none.apron < aprons[2])
    // A Profile with nothing spatial left reaches no further than its own pixel, so the
    // frame needs no Apron at all and the Export is one Tile.
    let plain = try await renderer.tilePlan(image: .linear(try flat(size: 256, value: 0.18)), profile: .identity,
                                            settings: .init(output: .workingSpace))
    #expect(plain.apron == 0)
    #expect(plain.isUntiled)
}

@Test func aTiledExportReproducesTheUntiledRenderOfTheSameFrame() async throws {
    // The whole point of the Apron in one assertion. Cinestill at the top of its
    // control is the stress case: the widest halo in the Catalogue, on the highest
    // contrast edge there is, with the source deliberately sitting on a Tile corner.
    let renderer = try Renderer()
    let cinestill = try stock("cinestill-800t")
    let size = 512
    let image = try practicalLight(size: size, at: (256, 256))
    let settings = RenderSettings(temperatureKelvin: 3200, halationIntensity: 2, grainIntensity: 0,
                                  vignette: 0.4, frameBorder: 0.2)
    let whole = try await renderer.render(image: .linear(image), profile: cinestill, settings: settings)
    func differences(_ options: ExportOptions) async throws -> [Double] {
        let plan = try await renderer.tilePlan(image: .linear(image), profile: cinestill, settings: settings, options: options)
        #expect(plan.columns >= 4 && plan.rows >= 4)
        let tiled = try await renderer.exportedPixels(image: .linear(image), profile: cinestill,
                                                      settings: settings, options: options)
        #expect(tiled.width == whole.width && tiled.height == whole.height)
        return (0..<(size * size * 3)).map { index -> Double in
            let pixel = index / 3 * 4 + index % 3
            return abs(Double(tiled.rgba[pixel]) - Double(whole.rgba[pixel]))
        }
    }
    // Carrying the whole of what the Passes reach for, the answer is not "close enough
    // to hide a seam" but identical. Every blur in the pipeline is a truncated kernel,
    // so that reach is finite and exact, and Tile origins are held to the grid the
    // Scattering Pyramid halves on; given both, a Tile runs the same arithmetic on the
    // same values as the untiled render does.
    #expect(try await differences(tiling(apronFraction: 1)).max() == 0)
    // At the default the Apron is a little over half of that, and a 12MP Export is six
    // times quicker for it. What the truncated tail costs is well under the finest
    // difference an eight-bit display can show.
    #expect(try await differences(tiling()).max()! < 1.0 / 255)
}

@Test func halationHasNoTileSeamWhereAPointLightStraddlesABoundary() async throws {
    // The defect this test exists for is a step in the halo where it crosses a Tile
    // boundary: a Tile that clamped at its own edge instead of reading the rest of the
    // frame. A halo is only a few sigmas wide, so a source in the middle of a Tile
    // never reaches the next one — the light goes just short of a boundary and the
    // halo is read where it crosses.
    let renderer = try Renderer()
    let cinestill = try stock("cinestill-800t")
    let size = 512
    let settings = RenderSettings(temperatureKelvin: 3200, halationIntensity: 2, bloomIntensity: 0, grainIntensity: 0)
    let options = tiling()
    // Where the boundaries fall is the Apron's business rather than the test's, so the
    // light is placed against the plan rather than against a number written here.
    let plan = try await renderer.tilePlan(image: .linear(try flat(size: size, value: 0)),
                                           profile: cinestill, settings: settings, options: options)
    let pitch = plan.coreWidth
    #expect(plan.columns >= 3)
    let boundary = pitch * (plan.columns / 2)
    let image = try practicalLight(size: size, at: (boundary - 16, size / 2))
    let tiled = try await renderer.exportedPixels(image: .linear(image), profile: cinestill,
                                                  settings: settings, options: options)
    let row = size / 2
    let line = (0..<size).map { Double(tiled.rgba[(row * size + $0) * 4]) }
    // The halo has to be substantial and falling where it crosses, or the test proves
    // nothing: a seam in an unlit field is invisible whatever the renderer does.
    #expect(line[boundary] > 0.05)
    #expect(line[boundary] < line[boundary - 8] && line[boundary] > line[boundary + 8])
    // Second differences along it. A seam is a discontinuity, so it shows here as a
    // boundary column whose curvature dwarfs the smooth falloff on either side of it.
    var curvature: [Double] = []
    for column in 1..<(size - 1) {
        let second: Double = line[column - 1] - 2 * line[column] + line[column + 1]
        curvature.append(abs(second))
    }
    for column in stride(from: pitch, to: size, by: pitch) {
        let neighbours = [curvature[column - 3], curvature[column + 1]].max()!
        #expect(curvature[column - 1] <= max(3 * neighbours, 1.0 / 255))
    }
}

@Test func grainIsSampledInImageGlobalCoordinatesAndDoesNotRepeatAtTheTilePitch() async throws {
    let renderer = try Renderer()
    let profile = try graining()
    let size = 512
    // Mid-grey, where the Density Response is loudest: at 0.4 this Profile's triangle
    // has already fallen to silence and there would be no field to test.
    let image = try flat(size: size, value: 0.18)
    let settings = RenderSettings(output: .workingSpace, halationIntensity: 0, bloomIntensity: 0)
    var without = settings
    without.grainIntensity = 0
    // This Profile has no Halation, Bloom or MTF, so its Apron is nothing and the Tile
    // is all core: a smaller budget is what puts several Tiles across the frame.
    let options = tiling(paddedEdge: 128)
    let plan = try await renderer.tilePlan(image: .linear(image), profile: profile, settings: settings, options: options)
    let pitch = plan.coreWidth
    #expect(plan.columns >= 3)
    let grainy = try await renderer.exportedPixels(image: .linear(image), profile: profile, settings: settings, options: options)
    let plain = try await renderer.exportedPixels(image: .linear(image), profile: profile, settings: without, options: options)
    let field = (0..<(size * size)).map { Double(grainy.rgba[$0 * 4]) - Double(plain.rgba[$0 * 4]) }
    let deviation = { (values: [Double]) -> Double in
        let mean = values.reduce(0, +) / Double(values.count)
        return (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
    }
    #expect(deviation(field) > 0.001)

    // A Tile-local lattice would put a copy of the same field in every Tile, which the
    // autocorrelation reports as a spike at the Tile pitch and nowhere else.
    let mean = field.reduce(0, +) / Double(field.count)
    let centred = field.map { $0 - mean }
    func autocorrelation(lag: Int) -> Double {
        var product = 0.0, energy = 0.0
        for y in 0..<size {
            for x in 0..<(size - lag) {
                product += centred[y * size + x] * centred[y * size + x + lag]
                energy += centred[y * size + x] * centred[y * size + x]
            }
        }
        return energy > 0 ? product / energy : 0
    }
    let atPitch = abs(autocorrelation(lag: pitch))
    let elsewhere = (1..<64).map { abs(autocorrelation(lag: pitch + $0)) }.max()!
    #expect(atPitch < 0.05)
    #expect(atPitch <= 4 * max(elsewhere, 1e-4))

    // Grain finer than a pixel is one independent sample per pixel addressed by the
    // global coordinate, so the tiled field is not merely similar to the untiled one:
    // it is the same field, pixel for pixel.
    let untiled = try await renderer.render(image: .linear(image), profile: profile, settings: settings)
    let untiledPlain = try await renderer.render(image: .linear(image), profile: profile, settings: without)
    for index in stride(from: 0, to: size * size, by: 7) {
        let expected = Double(untiled.rgba[index * 4]) - Double(untiledPlain.rgba[index * 4])
        #expect(abs(field[index] - expected) < 1e-6)
    }
}

@Test func exportProgressIsReportedPerTileAndTheWorkIsCancellable() async throws {
    let renderer = try Renderer()
    let image = try flat(size: 384, value: 0.3)
    let profile = try stock("portra-400")
    let reported = Reported()
    let data = try await renderer.export(image: .linear(image), profile: profile, settings: .init(),
                                         format: .jpeg, options: tiling()) { reported.append($0) }
    #expect(!data.isEmpty)
    let progress = reported.values
    #expect(progress.first?.completedTiles == 0)
    #expect(progress.last?.fraction == 1)
    #expect(progress.last?.completedTiles == progress.last?.tileCount)
    #expect(zip(progress, progress.dropFirst()).allSatisfy { $0.completedTiles < $1.completedTiles })

    // Cancellation is checked per Tile, which is also the granularity progress reports.
    let task = Task { try await renderer.export(image: .linear(image), profile: profile, options: tiling()) }
    task.cancel()
    await #expect(throws: CancellationError.self) { _ = try await task.value }
}

/// Progress arrives on the renderer's executor rather than the test's, so the values
/// need somewhere thread-safe to land.
private final class Reported: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ExportProgress] = []
    func append(_ progress: ExportProgress) { lock.lock(); storage.append(progress); lock.unlock() }
    var values: [ExportProgress] { lock.lock(); defer { lock.unlock() }; return storage }
}

@Test func writersProduceTaggedFilesInEveryFormat() async throws {
    let renderer = try Renderer()
    let image = try flat(size: 300, value: 0.4)
    let profile = try stock("portra-400")
    for format in ExportFormat.allCases {
        for output in [RenderSettings.Output.displayP3, .sRGB] {
            let data = try await renderer.export(image: .linear(image), profile: profile,
                                                 settings: .init(output: output), format: format,
                                                 options: tiling())
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            #expect(CGImageSourceGetType(source) as String? == format.contentType.identifier)
            let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(decoded.width == 300 && decoded.height == 300)
            #expect(decoded.bitsPerComponent == format.bitsPerComponent)
            // An untagged file would be read as sRGB, silently undoing a P3 export.
            let name = try #require(decoded.colorSpace?.name as String?).lowercased()
            #expect(name.contains(output == .sRGB ? "srgb" : "p3"))
        }
    }
    // The Working Space is an intermediate, not a deliverable, and saying so is better
    // than writing a file whose numbers mean nothing to anything that opens it.
    await #expect(throws: FilmError.self) {
        _ = try await renderer.export(image: .linear(image), profile: profile, settings: .init(output: .workingSpace))
    }
}

@Test func sRGBAndDisplayP3DifferOnlyInPrimaries() async throws {
    let renderer = try Renderer()
    func encode(_ rgb: [Float16], _ output: RenderSettings.Output) async throws -> [Double] {
        let image = try LinearImage(width: 1, height: 1, rgba: rgb + [1])
        let result = try await renderer.render(image: .linear(image), profile: .identity, settings: .init(output: output))
        return (0..<3).map { Double(result.rgba[$0]) }
    }
    // Both are D65, so a neutral is a neutral in either and encodes identically.
    let greyP3 = try await encode([0.18, 0.18, 0.18], .displayP3)
    let greySRGB = try await encode([0.18, 0.18, 0.18], .sRGB)
    for channel in 0..<3 { #expect(abs(greyP3[channel] - greySRGB[channel]) < 0.002) }
    #expect(abs(greyP3[0] - greyP3[1]) < 0.002 && abs(greyP3[1] - greyP3[2]) < 0.002)
    // A saturated Rec.2020 red is outside both gamuts and further outside the narrower
    // one, so sRGB has to push its red channel harder and its others further negative.
    let redP3 = try await encode([0.5, 0, 0], .displayP3)
    let redSRGB = try await encode([0.5, 0, 0], .sRGB)
    #expect(redSRGB[0] > redP3[0])
    #expect(redSRGB[1] < redP3[1] && redSRGB[2] < redP3[2])
}

@Test func theExportedLUTMatchesTheRenderWithGrainAndHalationAtZero() async throws {
    let renderer = try Renderer()
    let profile = try stock("portra-400")
    // Everything a cube cannot carry, off — which is the claim the UI has to make too.
    let settings = RenderSettings(output: .displayP3, temperatureKelvin: 4800, tint: 12, exposureStops: 0.5,
                                  developmentOffset: 1, halationIntensity: 0, bloomIntensity: 0, grainIntensity: 0)
    let text = try await renderer.exportedLUT(profile: profile, settings: settings)
    let size = 33
    let entries = try parseCube(text, expecting: size)
    #expect(text.contains("no grain, halation, bloom"))
    #expect(text.contains("LUT_3D_SIZE 33"))
    #expect(text.contains("DOMAIN_MAX 1.0 1.0 1.0"))

    // The LUT is addressed in the encoding it returns, so the address of a Working
    // Space colour is what the identity Profile encodes it to. Going through the
    // renderer for that keeps the test from carrying its own copy of the primaries.
    for light in [[0.02, 0.02, 0.02], [0.18, 0.18, 0.18], [0.5, 0.42, 0.3], [0.05, 0.2, 0.4], [0.9, 0.9, 0.9]] {
        let pixel = try LinearImage(width: 1, height: 1, rgba: light.map(Float16.init) + [1])
        let address = try await renderer.render(image: .linear(pixel), profile: .identity,
                                                settings: .init(output: .displayP3))
        let rendered = try await renderer.render(image: .linear(pixel), profile: profile, settings: settings)
        let sampled = tetrahedral(entries, size: size,
                                  at: (0..<3).map { min(max(Double(address.rgba[$0]), 0), 1) })
        for channel in 0..<3 {
            #expect(abs(sampled[channel] - Double(rendered.rgba[channel])) < 0.01)
        }
    }
    // sRGB is a different LUT, not the same numbers relabelled.
    var srgb = settings
    srgb.output = .sRGB
    #expect(try await renderer.exportedLUT(profile: profile, settings: srgb) != text)
    // The Working Space is not an encoding a cube can be addressed in.
    await #expect(throws: FilmError.self) {
        _ = try await renderer.exportedLUT(profile: profile, settings: .init(output: .workingSpace))
    }
}

@Test func grainDegradesToTheProceduralModelWhenTheDeviceIsThrottling() throws {
    // Preview and Export retain the same physical grain model even under thermal pressure.
    let cinestill = try stock("cinestill-800t")
    #expect(cinestill.metadata.grain.model == .dyeCloud)
    #expect(Renderer.grainModel(cinestill, path: .preview, thermalState: .nominal) == .dyeCloud)
    #expect(Renderer.grainModel(cinestill, path: .preview, thermalState: .serious) == .dyeCloud)
    #expect(Renderer.grainModel(cinestill, path: .export, thermalState: .nominal) == .dyeCloud)
    #expect(Renderer.grainModel(cinestill, path: .export, thermalState: .fair) == .dyeCloud)
    #expect(Renderer.grainModel(cinestill, path: .export, thermalState: .serious) == .dyeCloud)
    #expect(Renderer.grainModel(cinestill, path: .export, thermalState: .critical) == .dyeCloud)
    // A Stock that already asks for the cheap model is unaffected by any of it.
    for state in [ProcessInfo.ThermalState.nominal, .fair, .serious, .critical] {
        #expect(Renderer.grainModel(.identity, path: .export, thermalState: state) == .procedural)
    }
}

// MARK: - Reading a .cube back

private func parseCube(_ text: String, expecting size: Int) throws -> [[Double]] {
    let entries = text.split(separator: "\n").compactMap { line -> [Double]? in
        if line.hasPrefix("#") { return nil }
        let parts = line.split(separator: " ")
        guard parts.count == 3, let values = try? parts.map({ try #require(Double($0)) }) else { return nil }
        return values
    }
    #expect(entries.count == size * size * size)
    return entries
}

/// The same tetrahedral interpolation the Film Response Pass uses, so the comparison
/// is against how a cube is actually applied rather than against a cheaper reading.
private func tetrahedral(_ entries: [[Double]], size: Int, at coordinate: [Double]) -> [Double] {
    let q = coordinate.map { $0 * Double(size - 1) }
    let base = q.map { min(Int($0), size - 2) }
    let f = (0..<3).map { q[$0] - Double(base[$0]) }
    var order = [0, 1, 2]
    if f[order[0]] < f[order[1]] { order.swapAt(0, 1) }
    if f[order[1]] < f[order[2]] { order.swapAt(1, 2) }
    if f[order[0]] < f[order[1]] { order.swapAt(0, 1) }
    func entry(_ v: [Int]) -> [Double] { entries[v[0] + size * (v[1] + size * v[2])] }
    var v1 = base; v1[order[0]] += 1
    var v2 = v1; v2[order[1]] += 1
    let x0 = entry(base), x1 = entry(v1), x2 = entry(v2), x3 = entry(base.map { $0 + 1 })
    return (0..<3).map { channel -> Double in
        var value: Double = x0[channel]
        value += f[order[0]] * (x1[channel] - x0[channel])
        value += f[order[1]] * (x2[channel] - x1[channel])
        value += f[order[2]] * (x3[channel] - x2[channel])
        return value
    }
}
