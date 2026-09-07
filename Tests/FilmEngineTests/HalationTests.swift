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
    // The same scene at four resolutions must scatter across the same fraction of the
    // frame. Only a micron radius converted through Frame Width does that, and only a
    // pyramid deep enough for the radius keeps doing it as the frame grows: these
    // radii ask for 12 pixels of sigma at 256 and 96 at 2048, four levels apart.
    let renderer = try Renderer()
    let profile = try scattering(strength: 0.5, threshold: 1, radiusMicrons: [1680, 720, 360])
    var profiles: [[Double]] = []
    for size in [256, 512, 1024, 2048] {
        let result = try await renderer.render(image: .linear(try point(width: size, height: size, value: 64, radius: size / 64)),
                                               profile: profile, settings: .init(output: .workingSpace))
        let centre = Double(result.rgba[((size / 2) * size + size / 2) * 4])
        profiles.append((1...12).map { Double(result.rgba[((size / 2) * size + size / 2 + $0 * size / 256) * 4]) / centre })
    }
    for other in profiles.dropFirst() {
        for (small, large) in zip(profiles[0], other) { #expect(abs(small - large) < 0.06) }
    }
    // Frame Width is the frame's long edge, which a portrait photograph records down
    // its height. Rotating the camera must not change how far the light scatters.
    var landscape = [Float16](repeating: 0, count: 512 * 256 * 4)
    for i in stride(from: 3, to: landscape.count, by: 4) { landscape[i] = 1 }
    for y in 126...130 { for x in 254...258 { for c in 0..<3 { landscape[(y * 512 + x) * 4 + c] = 64 } } }
    var portrait = [Float16](repeating: 0, count: 512 * 256 * 4)
    for i in stride(from: 3, to: portrait.count, by: 4) { portrait[i] = 1 }
    for y in 254...258 { for x in 126...130 { for c in 0..<3 { portrait[(y * 256 + x) * 4 + c] = 64 } } }
    let wide = try await renderer.render(image: .linear(try LinearImage(width: 512, height: 256, rgba: landscape)),
                                         profile: profile, settings: .init(output: .workingSpace))
    let tall = try await renderer.render(image: .linear(try LinearImage(width: 256, height: 512, rgba: portrait)),
                                         profile: profile, settings: .init(output: .workingSpace))
    for distance in 1...40 {
        let across = Double(wide.rgba[((128) * 512 + 256 + distance) * 4])
        let down = Double(tall.rgba[((256 + distance) * 256 + 128) * 4])
        #expect(abs(across - down) < 0.02 + 0.04 * across)
    }
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

/// Rewrites a shipped Profile's metadata through the documented container layout.
/// Payload offsets are relative to the end of the header, so only the length prefix
/// moves.
private func rewriting(_ profile: Profile, _ edit: (inout [String: Any]) throws -> Void) throws -> Profile {
    let bytes = try ProfileContainer.encode(profile)
    let length = (0..<4).reduce(0) { $0 | Int(bytes[12 + $1]) << ($1 * 8) }
    var header = try #require(JSONSerialization.jsonObject(with: bytes.subdata(in: 16..<(16 + length))) as? [String: Any])
    var metadata = try #require(header["profile"] as? [String: Any])
    try edit(&metadata)
    header["profile"] = metadata
    let json = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
    var rebuilt = Data(bytes.prefix(12))
    for shift in stride(from: 0, to: 32, by: 8) { rebuilt.append(UInt8(truncatingIfNeeded: UInt32(json.count) >> shift)) }
    rebuilt.append(json)
    rebuilt.append(bytes.suffix(from: 16 + length))
    return try ProfileContainer.decode(rebuilt)
}

/// A 2048-pixel render of the result carries the pixel sigma an 8000-pixel frame
/// would ask this Stock for, without allocating one.
private func widening(_ profile: Profile, by factor: Double) throws -> Profile {
    try rewriting(profile) { metadata in
        var halation = try #require(metadata["halation"] as? [String: Any])
        halation["radiusMicrons"] = try #require(halation["radiusMicrons"] as? [Double]).map { $0 * factor }
        metadata["halation"] = halation
    }
}

/// The same Stock with no spatial response, so the halo under test is the pyramid's.
private func flattening(_ profile: Profile) throws -> Profile {
    try rewriting(profile) { metadata in
        var mtf = try #require(metadata["mtf"] as? [String: Any])
        let cycles: [Double] = try #require(mtf["cyclesPerMM"] as? [Double])
        mtf["response"] = [Double](repeating: 1, count: cycles.count)
        metadata["mtf"] = mtf
    }
}

@Test func cinestillHaloIsSmoothAtFullStrength() async throws {
    // The stress case: the largest radius and strength in the Catalogue, at the top of
    // the user's control, on the highest contrast edge there is. Banding would show as
    // a staircase — flat runs separated by steps — in the radial falloff. Grain is off,
    // because a fluctuation the Stock is supposed to have would read here as the defect
    // this test is looking for. The Stock's own MTF stays on for the shipped case,
    // because banding is what is under test and the MTF Pass is part of what could
    // cause it; only the strictly monotone falloff is asked of the flattened cases,
    // since the published curve sits above one at low frequency and that adjacency
    // overshoot at the edge of the source is development, not a step in the pyramid.
    let renderer = try Renderer()
    let cinestill = try stock("cinestill-800t")
    // The last case is this Stock's radius at Export resolution, where the pyramid is
    // deepest and its coarsest level is stretched furthest.
    let smooth = try flattening(cinestill), widest = try flattening(try widening(cinestill, by: 4))
    for (size, profile, monotone) in [(512, smooth, true), (1024, smooth, true), (2048, smooth, true),
                                      (2048, widest, true), (1024, cinestill, false), (2048, cinestill, false)] {
        let result = try await renderer.render(image: .linear(try practicalLight(size: size)), profile: profile,
                                               settings: .init(temperatureKelvin: 3200, halationIntensity: 2, grainIntensity: 0))
        let centre = size / 2
        for (dx, dy) in [(1, 0), (0, 1), (1, 1)] {
            let line = ((size / 40 + 2)..<(size / 2 - 2)).map {
                Double(result.rgba[((centre + $0 * dy) * size + centre + $0 * dx) * 4])
            }
            let halo = Array(line.prefix { $0 > 0.02 })
            #expect(halo.count > 15)
            // Banding is a staircase in what the display shows: a plateau, then a jump.
            // Work in 8-bit code values, below which nothing is visible anyway — the
            // float16 signal is finer than that and wobbles by an ulp on a flat halo top.
            // In a smooth falloff a plateau means the slope is under one code value per
            // pixel, so the step that ends it can only be one. A steep single-pixel
            // descent is an edge, not a band, and is left alone.
            let codes = halo.map { Int(($0 * 255).rounded()) }
            var plateau = 1
            for (near, far) in zip(codes, codes.dropFirst()) {
                // One code value is the display's own resolution: a wobble that small
                // cannot render as a band, whatever it does to the float16 signal.
                #expect(far <= near + 1)
                if far >= near { plateau += 1 } else { #expect(plateau == 1 || near - far <= 2); plateau = 1 }
            }
            // Averaged over four samples the falloff is strictly monotone, so the wobble
            // above is quantisation and not a reversal in the halo itself.
            let smoothed = (0...(halo.count - 4)).map { halo[$0..<($0 + 4)].reduce(0, +) }
            if monotone { #expect(zip(smoothed, smoothed.dropFirst()).allSatisfy { $0 >= $1 }) }
            // A banded falloff also collapses onto a handful of levels; this one does not.
            #expect(Set(codes).count > halo.count / 3)
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
    // Sample where the halo is halfway up: unlit without Halation, burning red with
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
    let size = vision3.metadata.colour.lutSize
    let payloadBytes = size * size * size * 8 * vision3.metadata.colour.lutVariants.count
    #expect(try ProfileContainer.encode(vision3).suffix(payloadBytes) == ProfileContainer.encode(cinestill).suffix(payloadBytes))
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
