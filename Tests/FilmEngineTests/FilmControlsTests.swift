import Testing
import Foundation
import FilmEngine

private func portra() throws -> Profile {
    try #require(ProfileCatalogue.bundled().profiles.first { $0.id == "portra-400" })
}

private func render(_ renderer: Renderer, _ rgb: [Float16], profile: Profile, settings: RenderSettings) async throws -> [Float] {
    let result = try await renderer.render(image: .linear(try LinearImage(width: rgb.count / 3, height: 1, rgba: rgb.chunks(of: 3).flatMap { $0 + [1] })),
        profile: profile, settings: settings)
    return result.rgba.map(Float.init)
}

private extension Array {
    func chunks(of size: Int) -> [[Element]] { stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) } }
}

@Test func exposureIsAScalarMultiplyInLinearLightBeforeTheFilmResponse() async throws {
    let renderer = try Renderer()
    let input: [Float16] = [0.25, 0.5, 0.125, -0.5, 4, 0]
    let doubled = try await render(renderer, input, profile: .identity, settings: .init(output: .workingSpace, exposureStops: 1))
    #expect(doubled == [0.5, 1, 0.25, 1, -1, 8, 0, 1])
    let halved = try await render(renderer, input, profile: .identity, settings: .init(output: .workingSpace, exposureStops: -1))
    #expect(halved == [0.125, 0.25, 0.0625, 1, -0.25, 2, 0, 1])
    // Pushing rates the Stock faster: with a one-variant Profile the offset clamps to 0.
    let clamped = try await render(renderer, input, profile: .identity, settings: .init(output: .workingSpace, developmentOffset: 1))
    #expect(clamped == input.map(Float.init).chunks(of: 3).flatMap { $0 + [1] })
    // For a pushable Stock, +1 push and +1 exposure cancel to the normal rating.
    let portra = try portra()
    let pushed = try await render(renderer, [0.18, 0.18, 0.18], profile: portra, settings: .init(output: .workingSpace, exposureStops: 1, developmentOffset: 1))
    let neutralPushed = try await render(renderer, [0.36, 0.36, 0.36], profile: portra, settings: .init(output: .workingSpace, exposureStops: 0, developmentOffset: 1))
    let underexposed = try await render(renderer, [0.18, 0.18, 0.18], profile: portra, settings: .init(output: .workingSpace, developmentOffset: 1))
    for c in 0..<3 {
        #expect(abs(pushed[c] - neutralPushed[c]) < 0.003)
        #expect(underexposed[c] < pushed[c])
    }
}

@Test func whiteBalanceAdaptsTheSceneIlluminantTowardTheStockBalance() async throws {
    let renderer = try Renderer()
    var tungsten = Profile.identity.metadata
    tungsten.balance = 3200
    let tungstenStock = try Profile(metadata: tungsten, payloads: ["identity.lut3d": ColourCube.identity.payload])
    let grey: [Float16] = [0.5, 0.5, 0.5]
    // A daylight scene through a tungsten Stock is correctly blue.
    let daylightOnTungsten = try await render(renderer, grey, profile: tungstenStock, settings: .init(output: .workingSpace, temperatureKelvin: 5500))
    #expect(daylightOnTungsten[2] > daylightOnTungsten[1] && daylightOnTungsten[1] > daylightOnTungsten[0])
    // Matching the Stock Balance with the Scene Illuminant restores neutrality exactly.
    let matched = try await render(renderer, grey, profile: tungstenStock, settings: .init(output: .workingSpace, temperatureKelvin: 3200))
    #expect(matched == [0.5, 0.5, 0.5, 1])
    // Tungsten light on a daylight Stock records warm.
    let tungstenOnDaylight = try await render(renderer, grey, profile: .identity, settings: .init(output: .workingSpace, temperatureKelvin: 3200))
    #expect(tungstenOnDaylight[0] > tungstenOnDaylight[1] && tungstenOnDaylight[1] > tungstenOnDaylight[2])
    // Neutral luminance is roughly preserved by the Bradford adaptation.
    let y = 0.2627 * tungstenOnDaylight[0] + 0.678 * tungstenOnDaylight[1] + 0.0593 * tungstenOnDaylight[2]
    #expect(abs(y - 0.5) < 0.03)
    // Tint moves perpendicular to the locus: positive is magenta, negative green.
    let magenta = try await render(renderer, grey, profile: .identity, settings: .init(output: .workingSpace, tint: 40))
    let green = try await render(renderer, grey, profile: .identity, settings: .init(output: .workingSpace, tint: -40))
    #expect(magenta[1] < magenta[0] && magenta[1] < magenta[2])
    #expect(green[1] > green[0] && green[1] > green[2])
    #expect(abs(magenta[1] - green[1]) > 0.02)
    // The pass happens before the Film Response: the Portra scan sees a warm scene as warm.
    let portra = try portra()
    let warm = try await render(renderer, [0.18, 0.18, 0.18], profile: portra, settings: .init(output: .workingSpace, temperatureKelvin: 3200))
    #expect(warm[0] > warm[2] + 0.02)
    await #expect(throws: FilmError.self) {
        _ = try await render(renderer, grey, profile: .identity, settings: .init(temperatureKelvin: 1000))
    }
    await #expect(throws: FilmError.self) {
        _ = try await render(renderer, grey, profile: .identity, settings: .init(tint: .nan))
    }
}

@Test func portraRendersMidGreyLowContrastAndMutedThroughTheBakedScan() async throws {
    let renderer = try Renderer()
    let portra = try portra()
    // The shaper maps scene-linear light to the spectral cube: mid-grey stays mid-grey.
    let grey = try await render(renderer, [0.18, 0.18, 0.18], profile: portra, settings: .init(output: .workingSpace))
    for c in 0..<3 { #expect(abs(grey[c] - 0.18) < 0.006) }
    // Two stops either side of grey respond with less than the linear ratio: low contrast, gentle rolloff.
    let wedge = try await render(renderer, [0.045, 0.045, 0.045, 0.72, 0.72, 0.72, 2.88, 2.88, 2.88], profile: portra, settings: .init(output: .workingSpace))
    #expect(wedge[0] > 0.045 && wedge[0] < 0.18)
    #expect(wedge[4] > 0.18 && wedge[4] < 0.72)
    #expect(wedge[8] > wedge[4] && wedge[8] < 1)
    // A saturated Rec.2020 red comes back with muted saturation.
    let red = try await render(renderer, [0.6, 0.05, 0.05], profile: portra, settings: .init(output: .workingSpace))
    #expect(red[0] > red[1] && red[0] > red[2])
    #expect((red[0] - Swift.min(red[1], red[2])) / red[0] < (0.6 - 0.05) / 0.6)
    // Beyond the shaper domain, output clamps instead of extrapolating.
    let extremes = try await render(renderer, [0, 0, 0, 1000, 1000, 1000], profile: portra, settings: .init(output: .workingSpace))
    #expect(extremes[0] >= 0 && extremes[4] <= 1 && extremes[4] > extremes[0])
}

@Test func developmentBlendsLinearlyBetweenTheNearestBakedVariants() async throws {
    let renderer = try Renderer()
    let portra = try portra()
    let input: [Float16] = [0.05, 0.05, 0.05, 0.18, 0.18, 0.18, 0.9, 0.9, 0.9, 0.5, 0.25, 0.1]
    func at(_ offset: Double) async throws -> [Float] {
        try await render(renderer, input, profile: portra, settings: .init(output: .workingSpace, exposureStops: offset, developmentOffset: offset))
    }
    let zero = try await at(0), one = try await at(1), quarter = try await at(0.25), half = try await at(0.5)
    for i in zero.indices {
        #expect(abs(half[i] - (zero[i] + one[i]) / 2) < 0.002)
        #expect(abs(quarter[i] - (0.75 * zero[i] + 0.25 * one[i])) < 0.002)
    }
    // Intermediate values are used rather than snapped, and the shape change is monotone.
    #expect(zip(zero, one).contains { abs($0 - $1) > 0.01 })
    #expect(half != zero && half != one)
    // Outside the baked range both the Colour Cube and the rating clamp.
    let beyond = try await render(renderer, input, profile: portra, settings: .init(output: .workingSpace, exposureStops: 2, developmentOffset: 3))
    let two = try await at(2)
    #expect(beyond == two)
}

@Test func scanOutputStageInvertsAndAutoBalancesDensitySpaceCubes() async throws {
    let renderer = try Renderer()
    let study = try #require(ProfileCatalogue.bundled().profiles.first { $0.id == "study-c41" })
    let input: [Float16] = [0.02, 0.02, 0.02, 0.18, 0.18, 0.18, 0.9, 0.9, 0.9]
    let scanned = try await render(renderer, input, profile: study, settings: .init(output: .workingSpace))
    let density = try await render(renderer, input, profile: study, settings: .init(output: .workingSpace, outputStage: OutputStage.none))
    // Density rises with exposure; the scan turns it back into a positive with mid-grey at 0.18.
    #expect(density[0] < density[4] && density[4] < density[8])
    #expect(scanned[0] < scanned[4] && scanned[4] < scanned[8])
    for c in 0..<3 { #expect(abs(scanned[4 + c] - 0.18) < 0.003) }
    #expect(scanned.allSatisfy { $0 >= 0 && $0 <= 1 })
    // Base density is the scan's black point.
    let black = try await render(renderer, [0, 0, 0], profile: study, settings: .init(output: .workingSpace))
    #expect(black[0] == 0 && black[1] == 0 && black[2] == 0)
    // Reversal and the spectral cube, whose scan is baked, are not inverted again.
    let reversal = try #require(ProfileCatalogue.bundled().profiles.first { $0.id == "study-e6" })
    let e6 = try await render(renderer, input, profile: reversal, settings: .init(output: .workingSpace))
    let e6Density = try await render(renderer, input, profile: reversal, settings: .init(output: .workingSpace, outputStage: OutputStage.none))
    #expect(e6 == e6Density)
    let portra = try portra()
    let scan = try await render(renderer, input, profile: portra, settings: .init(output: .workingSpace))
    let noStage = try await render(renderer, input, profile: portra, settings: .init(output: .workingSpace, outputStage: OutputStage.none))
    #expect(scan == noStage)
    // Monochrome Density Curves are scanned through the same auto-balance.
    let mono = try #require(ProfileCatalogue.bundled().profiles.first { $0.id == "study-bw-silver" })
    let bw = try await render(renderer, input, profile: mono, settings: .init(output: .workingSpace))
    #expect(bw[0] < bw[4] && bw[4] < bw[8])
    for c in 0..<3 { #expect(abs(bw[4 + c] - 0.18) < 0.003) }
    await #expect(throws: FilmError.self) {
        _ = try await render(renderer, input, profile: study, settings: .init(outputStage: .print))
    }
}

@Test func previewDecodeDownsamplesInTheWorkingSpaceAndMatchesFullDecode() async throws {
    let directory = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    let data = try Data(contentsOf: directory.appendingPathComponent("linear-high.dng"))
    let renderer = try Renderer()
    let full = try await renderer.decode(data)
    let preview = try await renderer.decode(data, maximumDimension: max(full.width, full.height) / 2)
    #expect(max(preview.width, preview.height) == max(full.width, full.height) / 2)
    let fullCenter = (full.height / 2 * full.width + full.width / 2) * 4
    let previewCenter = (preview.height / 2 * preview.width + preview.width / 2) * 4
    for c in 0..<3 { #expect(abs(Float(full.rgba[fullCenter + c]) - Float(preview.rgba[previewCenter + c])) < 0.01) }
    let rendered = try await renderer.render(image: .linear(full), profile: .identity, settings: .init(output: .workingSpace))
    let direct = try await renderer.render(image: .encoded(data), profile: .identity, settings: .init(output: .workingSpace))
    #expect(rendered.rgba == direct.rgba)
    await #expect(throws: FilmError.self) { _ = try await renderer.decode(data, maximumDimension: 0) }
}

@Test func previewRenderAndStockSwitchStayWithinInteractiveBudgets() async throws {
    // A screen-sized Preview: 1290×2796 is the largest iPhone canvas the spec names.
    let width = 1290, height = 2796
    var rgba = [Float16](repeating: 1, count: width * height * 4)
    for i in stride(from: 0, to: rgba.count, by: 4) {
        rgba[i] = Float16(Float(i % 977) / 977); rgba[i + 1] = Float16(Float(i % 331) / 331); rgba[i + 2] = Float16(Float(i % 113) / 113)
    }
    let image = try LinearImage(width: width, height: height, rgba: rgba)
    let renderer = try Renderer()
    let portra = try portra()
    let clock = ContinuousClock()
    // Cold: Colour Cubes are read from the bundle and uploaded on the first render.
    let coldStart = clock.now
    _ = try await renderer.render(image: .linear(image), profile: portra, settings: .init(developmentOffset: 0.5))
    let cold = clock.now - coldStart
    var warm: [Duration] = []
    for step in 1...5 {
        let start = clock.now
        _ = try await renderer.render(image: .linear(image), profile: portra, settings: .init(exposureStops: Double(step) / 3, developmentOffset: 0.5))
        warm.append(clock.now - start)
    }
    let best = warm.min()!
    print("Preview render: cold \(cold), warm best \(best), warm all \(warm)")
    // Generous CI bounds; the 16 ms / 100 ms targets are checked on device.
    #expect(cold < .milliseconds(1500))
    #expect(best < .milliseconds(400))
}
