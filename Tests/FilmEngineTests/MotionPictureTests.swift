import Testing
import Foundation
import FilmEngine

private func stock(_ id: String) throws -> Profile {
    try #require(ProfileCatalogue.bundled().profiles.first { $0.id == id })
}

/// The four Kodak Vision3 stocks, in the order their box speeds run.
private let vision3 = ["vision3-50d", "vision3-200t", "vision3-250d", "vision3-500t"]

/// A neutral ramp in stops around Working Space mid-grey, rendered as light rather
/// than as a Colour Cube coordinate.
private func ramp(_ stops: [Double]) throws -> LinearImage {
    let rgba = stops.flatMap { stop -> [Float16] in
        let value = Float16(0.18 * pow(2, stop))
        return [value, value, value, 1]
    }
    return try LinearImage(width: stops.count, height: 1, rgba: rgba)
}

/// The Film Response and its Output Stage alone. The scattering Passes would spread
/// one bright sample of a small ramp across the rest of it, which is not what any of
/// these probes is measuring.
private func settings(_ stage: OutputStage? = nil, kelvin: Double = RenderSettings.defaultTemperatureKelvin,
                      offset: Double = 0) -> RenderSettings {
    RenderSettings(output: .workingSpace, temperatureKelvin: kelvin, developmentOffset: offset,
                   halationIntensity: 0, bloomIntensity: 0, grainIntensity: 0, outputStage: stage)
}

/// The same, with the Scene Illuminant on the Stock's own balance and both ratings
/// backed out, so a scene value of 0.18 arrives at the Curve Set's own reference
/// neutral rather than where a meter set to True Speed or to a push would put it.
/// This is what `wedgeSettings` does for the Step Wedge, and for the same reason.
private func referenced(_ stage: OutputStage? = nil, _ profile: Profile, offset: Double = 0) -> RenderSettings {
    var settings = settings(stage, kelvin: profile.metadata.balance, offset: offset)
    settings.exposureStops = offset - log2(profile.metadata.nominalISO / profile.metadata.trueISO)
    return settings
}

private func channel(_ pixels: RenderedPixels, _ index: Int, _ channel: Int) -> Double {
    Double(pixels.rgba[index * 4 + channel])
}

private func average(_ pixels: RenderedPixels, _ index: Int) -> Double {
    (0..<3).reduce(0.0) { $0 + channel(pixels, index, $1) } / 3
}

@Test func theECN2BranchIsTheFourVision3StocksBalancedAsKodakPublishesThem() throws {
    let catalogue = try ProfileCatalogue.bundled().profiles
    #expect(Set(catalogue.filter { $0.metadata.process == .ecn2 }.map(\.id)) == Set(vision3 + ["study-ecn2"]))
    // Two daylight stocks and two tungsten ones, each at the exposure index its
    // datasheet prints, and each metered at the speed it is sold as.
    let expected: [String: (iso: Double, balance: Double)] = [
        "vision3-50d": (50, 5500), "vision3-250d": (250, 5500),
        "vision3-200t": (200, 3200), "vision3-500t": (500, 3200),
    ]
    for (id, published) in expected {
        let metadata = try stock(id).metadata
        #expect(metadata.nominalISO == published.iso)
        #expect(metadata.trueISO == published.iso)
        #expect(metadata.balance == published.balance)
        // 500T is Cinestill's parent Emulsion and was baked with it; the other three
        // are their own Curve Sets, and all four carry a measured source fingerprint.
        #expect(metadata.colour.sourceFingerprint != nil)
        #expect(metadata.provenance["spectral.characteristicCurves"] == .measured)
    }
    // Cinestill is the same Emulsion sold as a still film, so it is C-41 and derived
    // rather than a fifth ECN-2 Curve Set.
    #expect(try stock("cinestill-800t").metadata.derivedFrom == "vision3-500t")
}

@Test func remjetSuppressesHalationRelativeToStillNegative() async throws {
    // Every ECN-2 stock is remjet-backed, and the still colour negative in the
    // Catalogue is not. The modelled scattering says so in both of the terms that
    // decide a halo: how much light comes back, and how far it spreads.
    let portra = try stock("portra-400").metadata.halation
    for id in vision3 {
        let motion = try stock(id).metadata.halation
        #expect(motion.strength < portra.strength)
        for c in 0..<3 { #expect(motion.radiusMicrons[c] < portra.radiusMicrons[c]) }
    }
    // Cinestill 800T is the counter-example that gives the number its meaning: the
    // same Emulsion with the remjet washed off scatters far more, not less.
    let cinestill = try stock("cinestill-800t").metadata.halation
    #expect(cinestill.strength > portra.strength)
    #expect(cinestill.strength > (try stock("vision3-500t").metadata.halation.strength) * 50)

    // And it is the halo the renderer actually draws, not only the number. One
    // small bright light on a dark field; what is measured is all the light the
    // Halation Pass puts back into the frame, because the radii here are a
    // fraction of a pixel at any size a test wants to render and the strength is
    // what the integral answers to.
    let renderer = try Renderer()
    let width = 128, height = 128
    var rgba: [Float16] = []
    for y in 0..<height {
        for x in 0..<width {
            let lit = (x - 64) * (x - 64) + (y - 64) * (y - 64) < 64
            rgba += [Float16(lit ? 32 : 0.02), Float16(lit ? 32 : 0.02), Float16(lit ? 32 : 0.02), 1]
        }
    }
    let image = try LinearImage(width: width, height: height, rgba: rgba)
    func scattered(_ profile: Profile) async throws -> Double {
        // Halation is the only scattering Pass left on, and it is measured against
        // the same frame with the Pass off, so what is compared is the halo itself.
        // The Output Stage is off too: this is light before the Film Response, and
        // reading it in Density Space keeps a shoulder out of the comparison.
        var scattering = settings(OutputStage.none, kelvin: profile.metadata.balance)
        scattering.halationIntensity = 1
        var flat = scattering
        flat.halationIntensity = 0
        let with = try await renderer.render(image: .linear(image), profile: profile, settings: scattering)
        let without = try await renderer.render(image: .linear(image), profile: profile, settings: flat)
        return (0..<width * height).reduce(0.0) { $0 + abs(channel(with, $1, 0) - channel(without, $1, 0)) }
    }
    let still = try await scattered(try stock("portra-400"))
    #expect(still > 0)
    for id in vision3 { #expect(try await scattered(try stock(id)) < still) }
}

@Test func tungstenStockRecordsDaylightAsBlueAndTheRendererDoesNotCorrectIt() async throws {
    let renderer = try Renderer()
    let image = try ramp([0])
    // A 5500 K scene through a 3200 K stock. This is not a defect to be balanced
    // away: the film was manufactured for a different light, and the render says so.
    for id in ["vision3-200t", "vision3-500t"] {
        let profile = try stock(id)
        #expect(profile.metadata.balance == 3200)
        let daylight = try await renderer.render(image: .linear(image), profile: profile, settings: settings(kelvin: 5500))
        #expect(channel(daylight, 0, 2) > channel(daylight, 0, 0))
        // Blue enough to read as a cast rather than as a tint, in both directions
        // from grey: blue climbs and red falls away from a neutral of 0.18.
        #expect(channel(daylight, 0, 2) / channel(daylight, 0, 0) > 1.5)
        // The user can fix it, which is what makes leaving it alone a choice rather
        // than an omission: white balancing to the Stock's own balance is neutral.
        let matched = try await renderer.render(image: .linear(image), profile: profile,
                                                settings: settings(kelvin: profile.metadata.balance))
        #expect(abs(channel(matched, 0, 2) / channel(matched, 0, 0) - 1) < 0.02)
    }
    // The daylight-balanced Vision3 stocks record the same scene neutral, so the
    // cast above is the Stock Balance and not something the branch does to everyone.
    for id in ["vision3-50d", "vision3-250d"] {
        let profile = try stock(id)
        #expect(profile.metadata.balance == 5500)
        let daylight = try await renderer.render(image: .linear(image), profile: profile, settings: settings(kelvin: 5500))
        #expect(abs(channel(daylight, 0, 2) / channel(daylight, 0, 0) - 1) < 0.02)
    }
}

@Test func printIsOfferedForColourNegativesOnlyAndScanIsWhatTheProfileAsksFor() async throws {
    for profile in try ProfileCatalogue.bundled().profiles {
        let colour = profile.metadata.colour
        guard colour.printVariants != nil else {
            // Reversal film is the final image, black & white has no Colour Cube to
            // print from, and the two synthetic studies have no spectral model, so
            // none of them carries a Print for the editor to offer.
            #expect(profile.metadata.process == .e6 || profile.metadata.process.isMonochrome
                    || colour.inputShaper == nil)
            continue
        }
        #expect(profile.metadata.process == .c41 || profile.metadata.process == .ecn2)
        #expect(colour.outputStage == .scan)
        // Both Output Stages read the same negative, so both cover the same
        // Development Offsets. Film-density payloads are shared; observations differ.
        #expect(colour.printVariants!.map(\.pushStops).sorted() == colour.lutVariants.map(\.pushStops).sorted())
        let observation = try #require(colour.densityOutput)
        #expect(colour.printVariants == colour.lutVariants)
        #expect(Set(observation.printVariants!.map(\.lut)).isDisjoint(with: Set(observation.lutVariants.map(\.lut))))
    }
    // Scan is the default: a render that says nothing about the Output Stage is the
    // Profile's own, and the Profile's own is the scan.
    let renderer = try Renderer()
    let image = try ramp([-2, 0, 2])
    let profile = try stock("vision3-250d")
    let followed = try await renderer.render(image: .linear(image), profile: profile, settings: settings())
    let scanned = try await renderer.render(image: .linear(image), profile: profile, settings: settings(.scan))
    #expect(followed.rgba == scanned.rgba)
}

@Test func printAndScanAreDifferentPicturesOfTheSameNegative() async throws {
    let renderer = try Renderer()
    let stops = [-4.0, -3, -2, -1, 0, 1, 2, 3]
    let image = try ramp(stops)
    let midpoint = try #require(stops.firstIndex(of: 0))
    for id in ["portra-400", "cinestill-800t"] + vision3 {
        let profile = try stock(id)
        let scanned = try await renderer.render(image: .linear(image), profile: profile, settings: referenced(.scan, profile))
        let printed = try await renderer.render(image: .linear(image), profile: profile, settings: referenced(.print, profile))
        #expect(scanned.rgba != printed.rgba)
        // Both put the Curve Set's own reference neutral on Working Space mid-grey,
        // which is what makes the two comparable at all — the toggle changes the
        // picture rather than the exposure.
        #expect(abs(average(scanned, midpoint) - 0.18) < 0.02)
        #expect(abs(average(printed, midpoint) - 0.18) < 0.03)
        // A print of a neutral is neutral wherever there is enough of it to read:
        // the enlarger's filter pack is solved for exactly that, so what the paper
        // contributes is contrast, not a cast.
        for index in stops.indices where average(printed, index) > 0.05 {
            let spread = (0..<3).map { channel(printed, index, $0) }
            #expect(spread.max()! / spread.min()! < 1.2)
        }
        // Both climb with exposure, and the paper's own curve is far steeper than a
        // scanner's, so the print separates a stop around mid-grey by more.
        for index in 1..<stops.count { #expect(average(printed, index) > average(printed, index - 1)) }
        let printedSlope = average(printed, midpoint + 1) / average(printed, midpoint)
        let scannedSlope = average(scanned, midpoint + 1) / average(scanned, midpoint)
        #expect(printedSlope > scannedSlope)
        // And it pays for that with latitude at both ends: four stops under mid-grey
        // the print has run out of paper where the scan still holds separation.
        #expect(average(printed, 0) < average(scanned, 0))
        // Paper white is brighter than Working Space mid-grey by about three stops,
        // which is the paper's whole scale, and is carried rather than clipped.
        #expect(average(printed, stops.count - 1) > 1)
    }
}

@Test func askingAStockWithNoPrintForOneIsAnErrorRatherThanAScan() async throws {
    let renderer = try Renderer()
    let image = try ramp([0])
    // The two synthetic studies are the C-41 and ECN-2 Profiles with no Print, so
    // they are what proves the Print is refused rather than silently approximated.
    for id in ["study-c41", "study-ecn2", "tri-x-400"] {
        let profile = try stock(id)
        #expect(profile.metadata.colour.printVariants == nil)
        await #expect(throws: FilmError.self) {
            try await renderer.render(image: .linear(image), profile: profile, settings: settings(.print))
        }
    }
    // A reversal Stock has no Output Stage at all, so asking for a print cannot add
    // one any more than asking for a scan can: it renders the Transparency.
    for id in ["provia-100f", "study-e6"] {
        let profile = try stock(id)
        let followed = try await renderer.render(image: .linear(image), profile: profile, settings: settings())
        let printed = try await renderer.render(image: .linear(image), profile: profile, settings: settings(.print))
        #expect(followed.rgba == printed.rgba)
    }
}

@Test func printFollowsTheDevelopmentOffsetTheWayTheScanDoes() async throws {
    let renderer = try Renderer()
    // A stop either side of the reference neutral. The paper's scale is short, so a
    // wider probe measures the ends of it rather than the contrast across it.
    let image = try ramp([-1, 0, 1])
    let profile = try stock("vision3-500t")
    let neutral = try await renderer.render(image: .linear(image), profile: profile,
                                            settings: referenced(.print, profile, offset: 0))
    let pushed = try await renderer.render(image: .linear(image), profile: profile,
                                           settings: referenced(.print, profile, offset: 2))
    #expect(neutral.rgba != pushed.rgba)
    // Every Development Offset has its own print cube, and the lab prints each roll
    // to its own neutral, so the reference neutral still prints on mid-grey after a
    // push. What the push moves is the contrast around it.
    #expect(abs(average(pushed, 1) - average(neutral, 1)) < 0.03)
    #expect(average(pushed, 2) / average(pushed, 0) > average(neutral, 2) / average(neutral, 0))
}
