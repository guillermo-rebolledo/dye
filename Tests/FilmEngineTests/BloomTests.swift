import Testing
import Foundation
import FilmEngine

/// An identity Colour Cube isolates the Bloom Pass: whatever comes back is the light
/// the lens moved, not the Film Response's reading of it.
private func diffusing(strength: Double, radiusMicrons: Double = 900) throws -> Profile {
    var metadata = Profile.identity.metadata
    metadata.bloom = FilmProfile.Bloom(strength: strength, radiusMicrons: radiusMicrons)
    return try Profile(metadata: metadata, payloads: ["identity.lut3d": ColourCube.identity.payload])
}

private func point(width: Int, height: Int, value: Float16, radius: Int = 2) throws -> LinearImage {
    var rgba = [Float16](repeating: 0, count: width * height * 4)
    for i in stride(from: 3, to: rgba.count, by: 4) { rgba[i] = 1 }
    for y in (height / 2 - radius)...(height / 2 + radius) {
        for x in (width / 2 - radius)...(width / 2 + radius) {
            for c in 0..<3 { rgba[(y * width + x) * 4 + c] = value }
        }
    }
    return try LinearImage(width: width, height: height, rgba: rgba)
}

private func totalLight(_ pixels: [Float16]) -> Double {
    pixels.enumerated().filter { $0.offset % 4 == 0 }.map { Double($0.element) }.reduce(0, +)
}

@Test func bloomRedistributesTheLightTheLensAlreadyHadRatherThanAddingMore() async throws {
    // The distinction from Halation, which is a second exposure of the frame and
    // does add light. A lens cannot hand the film more than it received.
    let renderer = try Renderer()
    let size = 512
    let image = try point(width: size, height: size, value: 32)
    let result = try await renderer.render(image: .linear(image), profile: try diffusing(strength: 0.25),
                                           settings: .init(output: .workingSpace))
    let before = totalLight(image.rgba), after = totalLight(result.rgba)
    #expect(abs(after - before) / before < 0.005)
    // What the source lost is what the field around it gained.
    func centre(_ pixels: [Float16]) -> Double { Double(pixels[(size / 2 * size + size / 2) * 4]) }
    #expect(abs(centre(result.rgba) / centre(image.rgba) - 0.75) < 0.05)
    // The glare is neutral, and falls away monotonically in every channel alike.
    func sample(_ distance: Int, _ channel: Int) -> Double {
        Double(result.rgba[(size / 2 * size + size / 2 + distance) * 4 + channel])
    }
    for distance in stride(from: 8, to: 64, by: 4) {
        #expect(abs(sample(distance, 0) - sample(distance, 1)) < 1e-3)
        #expect(abs(sample(distance, 1) - sample(distance, 2)) < 1e-3)
    }
    let line = (8...100).map { sample($0, 0) }
    #expect(zip(line, line.dropFirst()).allSatisfy { $0 >= $1 })
    #expect(line[0] > 0.05)
}

@Test func bloomCoversTheSameFractionOfTheFrameAtEveryResolution() async throws {
    // Film-Plane Microns through Frame Width, exactly as Halation and Grain are
    // sized: a 900 µm sigma is a fortieth of a 36 mm frame at any pixel count.
    let renderer = try Renderer()
    let profile = try diffusing(strength: 0.5, radiusMicrons: 1800)
    var profiles: [[Double]] = []
    for size in [512, 1024, 2048] {
        let result = try await renderer.render(image: .linear(try point(width: size, height: size, value: 32, radius: size / 64)),
                                               profile: profile, settings: .init(output: .workingSpace))
        let centre = Double(result.rgba[(size / 2 * size + size / 2) * 4])
        profiles.append((1...12).map { Double(result.rgba[(size / 2 * size + size / 2 + $0 * size / 256) * 4]) / centre })
    }
    for other in profiles.dropFirst() {
        for (small, large) in zip(profiles[0], other) { #expect(abs(small - large) < 0.06) }
    }
    // Frame Width is the frame's long edge, in either orientation.
    var landscape = [Float16](repeating: 0, count: 512 * 256 * 4)
    for i in stride(from: 3, to: landscape.count, by: 4) { landscape[i] = 1 }
    for y in 126...130 { for x in 254...258 { for c in 0..<3 { landscape[(y * 512 + x) * 4 + c] = 32 } } }
    var portrait = [Float16](repeating: 0, count: 512 * 256 * 4)
    for i in stride(from: 3, to: portrait.count, by: 4) { portrait[i] = 1 }
    for y in 254...258 { for x in 126...130 { for c in 0..<3 { portrait[(y * 256 + x) * 4 + c] = 32 } } }
    let wide = try await renderer.render(image: .linear(try LinearImage(width: 512, height: 256, rgba: landscape)),
                                         profile: profile, settings: .init(output: .workingSpace))
    let tall = try await renderer.render(image: .linear(try LinearImage(width: 256, height: 512, rgba: portrait)),
                                         profile: profile, settings: .init(output: .workingSpace))
    for distance in 1...40 {
        let across = Double(wide.rgba[(128 * 512 + 256 + distance) * 4])
        let down = Double(tall.rgba[((256 + distance) * 256 + 128) * 4])
        #expect(abs(across - down) < 0.02 + 0.04 * across)
    }
}

@Test func bloomIntensityPreservesTheStockBelowTheDetentAndBoostsAboveIt() async throws {
    let renderer = try Renderer()
    let size = 256
    let image = try point(width: size, height: size, value: 32)
    let profile = try diffusing(strength: 0.1)
    // Zero is not a quiet Pass but no Pass: the frame is untouched.
    let off = try await renderer.render(image: .linear(image), profile: profile,
                                        settings: .init(output: .workingSpace, bloomIntensity: 0))
    #expect(off.rgba == image.rgba)
    func moved(_ intensity: Double) async throws -> Double {
        let result = try await renderer.render(image: .linear(image), profile: profile,
                                               settings: .init(output: .workingSpace, bloomIntensity: intensity))
        let centre = size / 2 * size + size / 2
        return Double(image.rgba[centre * 4]) - Double(result.rgba[centre * 4])
    }
    let half = try await moved(0.5), stock = try await moved(1), full = try await moved(2)
    #expect(abs(stock / half - 2) < 0.02)
    #expect(full > 2.5 * stock)
    // The default is the Profile's own lens rather than an invented number.
    #expect(RenderSettings().bloomIntensity == 1)
    #expect(RenderSettings.bloomRange == 0...2)
    for intensity in [-0.01, 2.01, Double.nan] {
        await #expect(throws: FilmError.self) {
            _ = try await renderer.render(image: .linear(image), profile: profile,
                                          settings: .init(output: .workingSpace, bloomIntensity: intensity))
        }
    }
}

@Test func bloomReachesTheEmulsionBeforeTheDensityCurvesDo() async throws {
    // The lens diffuses the light the film is about to record, so the Film Response
    // compresses the glare along with everything else. A post effect would add it
    // linearly. Doubling from 50% to 100% doubles the light moved before film
    // response; the creative range above 100% is deliberately nonlinear.
    let renderer = try Renderer()
    let portra = try #require(ProfileCatalogue.bundled().profiles.first { $0.id == "portra-400" })
    #expect(portra.metadata.bloom.strength > 0)
    let size = 512
    let image = try point(width: size, height: size, value: 64, radius: 16)
    func glare(_ intensity: Double) async throws -> Double {
        let result = try await renderer.render(image: .linear(image), profile: portra,
                                               settings: .init(output: .workingSpace, bloomIntensity: intensity, grainIntensity: 0))
        return Double(result.rgba[(size / 2 * size + size / 2 + 24) * 4])
    }
    // Just outside the lit disc, where the glare is strong and nothing is near the
    // top of the range, so what follows is compression rather than clipping.
    let (off, half, normal, full) = (try await glare(0), try await glare(0.5), try await glare(1), try await glare(2))
    #expect(normal > off + 0.2)
    #expect(full > normal)
    #expect(full < 0.85)
    #expect(normal - off < 1.7 * (half - off))
}
