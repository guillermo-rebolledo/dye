import Testing
import Foundation
import FilmEngine

/// An identity Colour Cube isolates the Halation Pass: whatever comes back is the
/// scattered light itself, not the Film Response's reading of it.
private func scattering(strength: Double, threshold: Double = 1,
                        radiusMicrons: [Double] = [220, 90, 45], tint: [Double] = [1, 1, 1]) throws -> Profile {
    var metadata = Profile.identity.metadata
    metadata.halation = FilmProfile.Halation(strength: strength, threshold: threshold, radiusMicrons: radiusMicrons, tint: tint)
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

@Test func halationThresholdUsesASmoothKneeRatherThanACutoff() async throws {
    // A one-pixel image has nothing to blur into, so the render reports the knee itself.
    let renderer = try Renderer()
    let threshold = 1.0, knee = 0.5
    let profile = try scattering(strength: 1, threshold: threshold)
    let step = 0.02
    let samples = stride(from: 0.0, through: 2.0, by: step).map { Double(Float16($0)) }
    var added: [Double] = []
    for value in samples {
        let x = Float16(value)
        let result = try await renderer.render(image: .linear(try LinearImage(width: 1, height: 1, rgba: [x, x, x, 1])),
                                               profile: profile, settings: .init(output: .workingSpace))
        added.append(Double(result.rgba[0]) - Double(x))
    }
    // The knee is the C1 quadratic joining zero to the excess across ±half the threshold.
    func expected(_ value: Double) -> Double {
        let d = value - threshold
        if d <= -knee { return 0 }
        return d >= knee ? d : (d + knee) * (d + knee) / (4 * knee)
    }
    for (value, amount) in zip(samples, added) {
        // Both ends of the subtraction are float16, so the tolerance follows the value.
        #expect(abs(amount - expected(value)) <= 0.002 + 0.002 * value)
    }
    // Below the knee nothing scatters at all; a hard cutoff would then jump by half a stop.
    #expect(zip(samples, added).allSatisfy { $0 >= threshold - knee || $1 == 0 })
    #expect(abs(added.last! - 1.0) < 0.01)
    // Slope stays inside 0...1 and never steps: the quantisation floor here is 0.05.
    let slopes = zip(added, added.dropFirst()).map { ($1 - $0) / step }
    #expect(slopes.allSatisfy { $0 >= -0.05 && $0 <= 1.05 })
    #expect(zip(slopes, slopes.dropFirst()).allSatisfy { abs($1 - $0) < 0.15 })
}

@Test func halationScattersFurthestInRedAndConservesTheScatteredLight() async throws {
    let renderer = try Renderer()
    let size = 1024
    let image = try point(width: size, height: size, value: 64)
    let profile = try scattering(strength: 0.5, threshold: 1)
    let result = try await renderer.render(image: .linear(image), profile: profile, settings: .init(output: .workingSpace))
    func sample(_ distance: Int, _ channel: Int) -> Double {
        Double(result.rgba[((size / 2) * size + size / 2 + distance) * 4 + channel])
    }
    // 220/90/45 µm on a 36 mm frame at 1024 pixels is 6.3/2.6/1.3 pixels. Compare each
    // channel's own falloff so the tint and the radius are measured separately.
    let reach = (0..<3).map { channel -> Int in
        let peak = sample(3, channel)
        return (3...200).last { sample($0, channel) > 0.02 * peak } ?? 3
    }
    #expect(reach[0] > reach[1] && reach[1] > reach[2])
    // Each channel falls away monotonically: a halo, not a ring of level steps.
    for channel in 0..<3 {
        let line = (3...60).map { sample($0, channel) }
        #expect(zip(line, line.dropFirst()).allSatisfy { $0 >= $1 })
    }
    // The blur is energy preserving, so the frame gains the scattered fraction of the
    // above-threshold light. 25 lit pixels of 64 scatter 0.5 × (64 − 1) each.
    let input = image.rgba.enumerated().filter { $0.offset % 4 == 0 }.map { Double($0.element) }.reduce(0, +)
    let output = result.rgba.enumerated().filter { $0.offset % 4 == 0 }.map { Double($0.element) }.reduce(0, +)
    #expect(abs((output - input) - 0.5 * 25 * 63) / (0.5 * 25 * 63) < 0.02)
}

@Test func halationRadiusFollowsTheFrameWidthRatherThanThePixelGrid() async throws {
    // The same scene at two resolutions must scatter across the same fraction of the
    // frame. Only a micron radius converted through Frame Width does that.
    let renderer = try Renderer()
    let profile = try scattering(strength: 0.5, threshold: 1)
    var profiles: [[Double]] = []
    for size in [256, 512] {
        let result = try await renderer.render(image: .linear(try point(width: size, height: size, value: 64, radius: size / 128)),
                                               profile: profile, settings: .init(output: .workingSpace))
        let centre = Double(result.rgba[((size / 2) * size + size / 2) * 4])
        profiles.append((1...12).map { Double(result.rgba[((size / 2) * size + size / 2 + $0 * size / 256) * 4]) / centre })
    }
    for (small, large) in zip(profiles[0], profiles[1]) { #expect(abs(small - large) < 0.06) }
}

private func stock(_ id: String) throws -> Profile {
    try #require(ProfileCatalogue.bundled().profiles.first { $0.id == id })
}

/// A small bright source on an unlit field: the scene Halation exists to describe.
private func practicalLight(size: Int, value: Float16 = 400) throws -> LinearImage {
    var rgba = [Float16](repeating: 0, count: size * size * 4)
    for i in stride(from: 3, to: rgba.count, by: 4) { rgba[i] = 1 }
    let centre = size / 2, radius = size / 40
    for y in (centre - radius)...(centre + radius) {
        for x in (centre - radius)...(centre + radius) {
            for c in 0..<3 { rgba[(y * size + x) * 4 + c] = value }
        }
    }
    return try LinearImage(width: size, height: size, rgba: rgba)
}

@Test func cinestillHaloIsSmoothAtFullStrength() async throws {
    // The stress case: the largest radius and strength in the Catalogue, at the top of
    // the user's control, on the highest contrast edge there is. Banding would show as
    // a staircase — flat runs separated by steps — in the radial falloff.
    let renderer = try Renderer()
    let cinestill = try stock("cinestill-800t")
    for size in [512, 1024, 2048] {
        let result = try await renderer.render(image: .linear(try practicalLight(size: size)), profile: cinestill,
                                               settings: .init(temperatureKelvin: 3200, halationIntensity: 2))
        let centre = size / 2
        for (dx, dy) in [(1, 0), (0, 1), (1, 1)] {
            let line = ((size / 40 + 2)..<(size / 2 - 2)).map {
                Double(result.rgba[((centre + $0 * dy) * size + centre + $0 * dx) * 4])
            }
            let halo = Array(line.prefix { $0 > 0.02 })
            #expect(halo.count > 15)
            var maximumStep = 0.0, run = 1, longestFlat = 1
            for (near, far) in zip(halo, halo.dropFirst()) {
                #expect(far <= near)
                maximumStep = max(maximumStep, near - far)
                if far == near { run += 1; longestFlat = max(longestFlat, run) } else { run = 1 }
            }
            // The falloff spends roughly its whole range over `halo.count` samples, so a
            // step much larger than the average is a band rather than a gradient.
            #expect(maximumStep * Double(halo.count) < 3)
            // Runs of two come from float16 spacing near the top of the halo; a band is longer.
            #expect(longestFlat <= 2)
        }
    }
}

@Test func halationReachesTheEmulsionBeforeTheDensityCurvesDo() async throws {
    let renderer = try Renderer()
    let cinestill = try stock("cinestill-800t")
    let size = 1024
    let image = try practicalLight(size: size)
    func render(_ intensity: Double) async throws -> [Float16] {
        try await renderer.render(image: .linear(image), profile: cinestill,
                                  settings: .init(temperatureKelvin: 3200, halationIntensity: intensity)).rgba
    }
    let (off, normal, full) = (try await render(0), try await render(1), try await render(2))
    // Sample where the halo is halfway up: unlit without Halation, glowing red with
    // it, and far from the top of the range so nothing below is about clipping.
    func index(_ distance: Int) -> Int { (size / 2 * size + size / 2 + distance) * 4 }
    let distance = (30..<(size / 2)).first { Double(normal[index($0)]) < 0.55 } ?? 50
    func channel(_ pixels: [Float16], _ c: Int) -> Double { Double(pixels[index(distance) + c]) }
    #expect(channel(off, 0) == 0)
    #expect(channel(normal, 0) > 0.4)
    #expect(channel(normal, 0) > 2 * channel(normal, 1))
    #expect(channel(normal, 1) > channel(normal, 2))
    // Doubling the scattered light must not double the result: the halo is exposure
    // that the density curves then compress. A post effect would add linearly, and
    // nothing here is near the top of the range, so this is not clipping either.
    #expect(channel(full, 0) < 0.85)
    #expect(channel(full, 0) < 1.5 * channel(normal, 0))
    #expect(channel(full, 0) > channel(normal, 0))
    // The control defaults to the Profile's own strength.
    let byDefault = try await renderer.render(image: .linear(image), profile: cinestill, settings: .init(temperatureKelvin: 3200)).rgba
    #expect(byDefault == normal)
    await #expect(throws: FilmError.self) {
        _ = try await renderer.render(image: .linear(image), profile: cinestill, settings: .init(halationIntensity: 2.5))
    }
}

@Test func cinestillIsVision3WithoutItsRemjetAndNothingElse() async throws {
    let cinestill = try stock("cinestill-800t"), vision3 = try stock("vision3-500t")
    #expect(cinestill.metadata.derivedFrom == "vision3-500t")
    #expect(vision3.metadata.derivedFrom == nil)
    // The Emulsion is one Emulsion: both Profiles carry the same baked Colour Cubes.
    #expect(vision3.metadata.colour.lutVariants == cinestill.metadata.colour.lutVariants)
    #expect(vision3.metadata.colour.inputShaper == cinestill.metadata.colour.inputShaper)
    #expect(try ProfileContainer.encode(vision3).suffix(1_149_984) == ProfileContainer.encode(cinestill).suffix(1_149_984))
    // Removing the Remjet backing raises Halation and nothing else about the light.
    #expect(cinestill.metadata.halation.strength > 50 * vision3.metadata.halation.strength)
    #expect(cinestill.metadata.halation.radiusMicrons[0] > vision3.metadata.halation.radiusMicrons[0])
    #expect(cinestill.metadata.balance == 3200 && vision3.metadata.balance == 3200)
    #expect(cinestill.metadata.mtf == vision3.metadata.mtf && cinestill.metadata.grain == vision3.metadata.grain)
    // Below both thresholds nothing scatters, so the two Stocks render identically.
    let renderer = try Renderer()
    let flat: [Float16] = [0.05, 0.05, 0.05, 1, 0.18, 0.2, 0.16, 1, 0.5, 0.4, 0.45, 1]
    let image = try LinearImage(width: 3, height: 1, rgba: flat)
    let settings = RenderSettings(output: .workingSpace, temperatureKelvin: 3200)
    #expect(try await renderer.render(image: .linear(image), profile: vision3, settings: settings).rgba
            == (try await renderer.render(image: .linear(image), profile: cinestill, settings: settings).rgba))
    // A tungsten Stock under daylight is correctly blue, and the renderer does not correct it.
    let daylight = try await renderer.render(image: .linear(try LinearImage(width: 1, height: 1, rgba: [0.18, 0.18, 0.18, 1])),
                                             profile: cinestill, settings: .init(output: .workingSpace, temperatureKelvin: 5500))
    #expect(daylight.rgba[2] > daylight.rgba[1] && daylight.rgba[1] > daylight.rgba[0])
}
