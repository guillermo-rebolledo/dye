import Testing
import Foundation
import FilmEngine

private func stock(_ id: String) throws -> Profile {
    try #require(ProfileCatalogue.bundled().profiles.first { $0.id == id })
}

/// A neutral ramp in stops around Working Space mid-grey, rendered as light rather
/// than as a Colour Cube coordinate, so both Stocks are given the same scene.
private func ramp(_ stops: [Double]) throws -> LinearImage {
    let rgba = stops.flatMap { stop -> [Float16] in
        let value = Float16(0.18 * pow(2, stop))
        return [value, value, value, 1]
    }
    return try LinearImage(width: stops.count, height: 1, rgba: rgba)
}

/// The Film Response alone: the scattering Passes spread a bright sample across a
/// small ramp, and a Stock's shoulder is not what they would be measuring.
private let unscattered = RenderSettings(output: .workingSpace, halationIntensity: 0, bloomIntensity: 0, grainIntensity: 0)

/// The mean of a sample's three channels. Not a Monochrome Collapse: these probes
/// are neutral, and what is being measured is how far up the curve they sit.
private func average(_ pixels: RenderedPixels, _ index: Int) -> Double {
    (0..<3).reduce(0.0) { $0 + Double(pixels.rgba[index * 4 + $1]) } / 3
}

@Test func reversalHasNoOutputStageAndTheCatalogueSaysSo() async throws {
    let catalogue = try ProfileCatalogue.bundled().profiles
    let reversal = catalogue.filter { $0.metadata.process == .e6 }
    #expect(Set(reversal.map(\.id)) == ["provia-100f", "velvia-50", "study-e6"])
    for profile in reversal {
        #expect(profile.metadata.colour.outputStage == FilmEngine.OutputStage.none)
        #expect(profile.metadata.monochrome == nil)
    }
    // Velvia meters slower than the box says, which is the whole reason True Speed
    // is a separate field from Box Speed.
    let velvia = try stock("velvia-50")
    #expect(velvia.metadata.nominalISO == 50)
    #expect(velvia.metadata.trueISO == 40)
    let provia = try stock("provia-100f")
    #expect(provia.metadata.nominalISO == provia.metadata.trueISO)
}

@Test func reversalSkipsInversionWhateverTheSettingsAskFor() async throws {
    let renderer = try Renderer()
    let image = try ramp([-3, -1, 0, 1, 3])
    // study-e6 is the case that matters most here: its cube is Density Space, so
    // the Output Stage is the only thing standing between it and an inversion.
    for id in ["provia-100f", "velvia-50", "study-e6"] {
        let profile = try stock(id)
        let followed = try await renderer.render(image: .linear(image), profile: profile, settings: .init(output: .workingSpace))
        // The Output Stage is skipped, so asking for a scan cannot inject one: the
        // Colour Cube already carries the transparency itself.
        let forced = try await renderer.render(image: .linear(image), profile: profile,
                                               settings: .init(output: .workingSpace, outputStage: .scan))
        let skipped = try await renderer.render(image: .linear(image), profile: profile,
                                                settings: .init(output: .workingSpace, outputStage: OutputStage.none))
        #expect(followed.rgba == forced.rgba)
        #expect(followed.rgba == skipped.rgba)
        // A reversal render is the Transparency: more light is a lighter frame throughout.
        for i in 1..<5 { #expect(average(followed, i) > average(followed, i - 1)) }
    }
    // The override is still how a negative is read in Density Space, which is what
    // the Step Wedge needs and what it must go on doing.
    let portra = try stock("portra-400")
    let scanned = try await renderer.render(image: .linear(image), profile: portra, settings: .init(output: .workingSpace))
    let study = try stock("study-c41")
    let density = try await renderer.render(image: .linear(image), profile: study,
                                            settings: .init(output: .workingSpace, outputStage: OutputStage.none))
    let inverted = try await renderer.render(image: .linear(image), profile: study, settings: .init(output: .workingSpace))
    #expect(scanned.rgba.count == inverted.rgba.count)
    #expect(density.rgba != inverted.rgba)
}

@Test func meteringUsesTrueSpeedRatherThanBoxSpeed() async throws {
    let renderer = try Renderer()
    let image = try ramp([0])
    // The Scene Illuminant is each Stock's own balance, so White Balance passes
    // through and a tungsten Stock is not being asked to render daylight neutral.
    func mid(_ profile: Profile, stops: Double = 0) async throws -> Double {
        let settings = RenderSettings(output: .workingSpace, temperatureKelvin: profile.metadata.balance,
                                      exposureStops: stops, halationIntensity: 0, bloomIntensity: 0, grainIntensity: 0)
        return average(try await renderer.render(image: .linear(image), profile: profile, settings: settings), 0)
    }
    // Each Curve Set puts its own reference neutral on Working Space mid-grey. A
    // Stock metered at Box Speed would land there; metering at True Speed is what
    // moves it, so backing the rating out again returns it exactly.
    for id in ["velvia-50", "cinestill-800t"] {
        let profile = try stock(id)
        let metadata = profile.metadata
        #expect(metadata.trueISO < metadata.nominalISO)
        let rating = log2(metadata.nominalISO / metadata.trueISO)
        #expect(abs(try await mid(profile, stops: -rating) - 0.18) < 0.005)
        // A Stock the box overstates is given more light, not less, so the same
        // scene comes out lighter than Box Speed metering would have made it.
        #expect(try await mid(profile) > (try await mid(profile, stops: -rating)))
    }
    // A Stock whose True Speed is its Box Speed is metered at the speed it is sold
    // as, and mid-grey lands on the reference neutral with no offset at all.
    for id in ["provia-100f", "portra-400"] {
        let profile = try stock(id)
        #expect(profile.metadata.trueISO == profile.metadata.nominalISO)
        #expect(abs(try await mid(profile) - 0.18) < 0.005)
    }
}
