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

private func luminance(_ pixels: RenderedPixels, _ index: Int) -> Double {
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
    for id in ["provia-100f", "velvia-50"] {
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
        // A reversal render is a positive: more light is a lighter frame throughout.
        for i in 1..<5 { #expect(luminance(followed, i) > luminance(followed, i - 1)) }
    }
}

@Test func reversalClipsHighlightsHarderThanColourNegativeAtMatchedExposure() async throws {
    let renderer = try Renderer()
    // Reversal holds roughly five stops against colour negative's twelve, so the
    // two part company well above mid-grey rather than at it.
    let image = try ramp([0, 4, 5, 6])
    let negative = try await renderer.render(image: .linear(image), profile: try stock("portra-400"), settings: unscattered)
    for id in ["provia-100f", "velvia-50"] {
        let reversal = try await renderer.render(image: .linear(image), profile: try stock(id), settings: unscattered)
        // Matched exposure: both Stocks put Working Space mid-grey back on mid-grey
        // and both are still climbing four stops above it.
        #expect(abs(luminance(reversal, 0) - 0.18) < 0.01)
        #expect(abs(luminance(negative, 0) - 0.18) < 0.01)
        #expect(luminance(reversal, 1) > luminance(reversal, 0))
        // Five stops over, the reversal Stock has run out of density to lose: a
        // sixth buys it nothing at all, where the negative is still recording.
        let headroom = luminance(reversal, 3) - luminance(reversal, 2)
        #expect(headroom < 0.002)
        #expect(headroom < luminance(negative, 3) - luminance(negative, 2))
    }
    #expect(luminance(negative, 3) - luminance(negative, 2) > 0.03)
}

@Test func reciprocityFailureIsPerChannelAndOnlyAboveTheThreshold() async throws {
    let renderer = try Renderer()
    let image = try ramp([0])
    let velvia = try stock("velvia-50")
    #expect(velvia.metadata.reciprocity.thresholdSeconds == 1)
    func render(_ profile: Profile, seconds: Double) async throws -> [Double] {
        let pixels = try await renderer.render(image: .linear(image), profile: profile,
                                               settings: .init(output: .workingSpace, exposureSeconds: seconds))
        return (0..<3).map { Double(pixels.rgba[$0]) }
    }
    // At and below the threshold the Stock obeys reciprocity exactly.
    let short = try await render(velvia, seconds: 1.0 / 125)
    #expect(try await render(velvia, seconds: 1) == short)
    // Thirty-two seconds is the last exposure Fujifilm publishes a correction for.
    let long = try await render(velvia, seconds: 32)
    for channel in 0..<3 { #expect(long[channel] < short[channel]) }
    // The green layer keeps more of its speed than red and blue, which is why the
    // published compensation is a magenta filter and not just a wider aperture.
    let gain = velvia.metadata.reciprocity.gain(seconds: 32)
    #expect(gain[1] > gain[0])
    #expect(abs(gain[0] - gain[2]) < 1e-12)
    // Fujifilm asks for a stop at 32 seconds; the fit through the whole published
    // table lands just under that rather than on the last row of it.
    #expect(abs(-log2(gain[0]) - 0.91) < 0.02)
    // A neutral stays neutral at a short exposure and does not at a long one: the
    // frame shifts colour as it darkens, which is the reason for three exponents.
    #expect(short.max()! - short.min()! < 0.001)
    #expect(long.max()! - long.min()! > 0.005)

    // Provia obeys reciprocity for a full two minutes, so the same exposure that
    // costs Velvia a stop costs it nothing at all.
    let provia = try stock("provia-100f")
    #expect(provia.metadata.reciprocity.thresholdSeconds == 128)
    #expect(try await render(provia, seconds: 32) == (try await render(provia, seconds: 1.0 / 125)))
    #expect(try await render(provia, seconds: 240)[0] < (try await render(provia, seconds: 1))[0])

    // A Curve Set that records no failure is unaffected at any exposure time.
    let portra = try stock("portra-400")
    #expect(portra.metadata.reciprocity.schwarzschildP == [1, 1, 1])
    #expect(try await render(portra, seconds: 3600) == (try await render(portra, seconds: 1.0 / 8000)))

    await #expect(throws: FilmError.self) {
        _ = try await renderer.render(image: .linear(image), profile: velvia, settings: .init(exposureSeconds: 0))
    }
}
