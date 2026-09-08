import Testing
import Foundation
import FilmEngine

private func stock(_ id: String) throws -> Profile {
    try #require(ProfileCatalogue.bundled().profiles.first { $0.id == id })
}

/// One row of linear Working Space light through a Profile, read back as floats.
private func render(_ renderer: Renderer, _ rgb: [[Float16]], profile: Profile,
                    settings: RenderSettings = .init(output: .workingSpace)) async throws -> [[Float]] {
    let image = try LinearImage(width: rgb.count, height: 1, rgba: rgb.flatMap { $0 + [1] })
    let result = try await renderer.render(image: .linear(image), profile: profile, settings: settings)
    return (0..<rgb.count).map { i in (0..<3).map { Float(result.rgba[i * 4 + $0]) } }
}

@Test(arguments: ["tri-x-400", "t-max-100"])
func aBlackAndWhiteStockCarriesADensityCurveAndNoColourCube(id: String) throws {
    let profile = try stock(id)
    #expect(profile.metadata.process == .bwSilver)
    #expect(profile.metadata.colour.lutVariants.isEmpty)
    #expect(profile.metadata.colour.cubeOutput == nil)
    let monochrome = try #require(profile.metadata.monochrome)
    // A 1024-entry float16 Density Curve is the whole Film Response payload.
    #expect(try ProfileContainer.encode(profile).count < 8 * 1024)
    let weight = try #require(monochrome.weight(for: .none))
    #expect(abs(weight.reduce(0, +) - 1) < 1e-9)
    // Not a luminance weighting: Rec.2020 luma would put roughly two thirds of the
    // weight on green, and a panchromatic emulsion under daylight does nothing of
    // the kind. Blue leads on both of these Stocks.
    #expect(weight[2] > weight[1] && weight[2] > weight[0])
    #expect(abs(weight[1] - 0.678) > 0.3)
    #expect(profile.metadata.provenance["monochrome.spectralWeight"] == .measured)
    #expect(profile.metadata.colour.sourceFingerprint?.count == 64)
}

@Test func theTwoStocksSeeColourDifferentlyAndSayHowByHowMuch() throws {
    let triX = try #require(try stock("tri-x-400").metadata.monochrome?.weight(for: .none))
    let tMax = try #require(try stock("t-max-100").metadata.monochrome?.weight(for: .none))
    // Two Profiles integrated from two digitised sensitivity curves. If either were a
    // shared luminance weighting these would be identical; T-Max is the greener of
    // the two and Tri-X the bluer, and that is what the Monochrome Collapse carries.
    #expect(triX != tMax)
    #expect(tMax[1] - triX[1] > 0.015)
    #expect(triX[2] - tMax[2] > 0.012)
}

/// How much lighter or darker a hue renders than a neutral of the same Rec.2020
/// luminance. Comparing against a matched neutral is what removes tone from the
/// question: two Stocks develop to different contrasts, so the same patch can land
/// either side of the other Stock's for reasons that have nothing to do with colour.
/// What is left is the Monochrome Collapse, which is the thing under test.
private func hueAgainstMatchedNeutral(_ renderer: Renderer, _ id: String, _ hue: [Float16]) async throws -> Float {
    let coefficients: [Double] = [0.2627, 0.6780, 0.0593]
    let luminance = Float16(zip(coefficients, hue).reduce(0) { $0 + $1.0 * Double($1.1) })
    let result = try await render(renderer, [hue, [luminance, luminance, luminance]], profile: try stock(id))
    return result[0][0] / result[1][0]
}

@Test func theTwoStocksRenderTheSameHueDifferentlyThroughTheWholePipeline() async throws {
    let renderer = try Renderer()
    func ratio(_ id: String, _ hue: [Float16]) async throws -> Float {
        try await hueAgainstMatchedNeutral(renderer, id, hue)
    }
    // Tri-X carries more of its weight on blue and T-Max more on green, so against a
    // luminance-matched neutral Tri-X lifts a blue subject and T-Max lifts a green
    // one, by around 5 % of scan value each way. Nothing about this survives if the
    // Spectral Weight is replaced by a shared luminance weighting.
    let blueOnTriX = try await ratio("tri-x-400", [0.06, 0.10, 0.50])
    let blueOnTMax = try await ratio("t-max-100", [0.06, 0.10, 0.50])
    #expect(blueOnTriX > blueOnTMax * 1.03)
    let greenOnTriX = try await ratio("tri-x-400", [0.06, 0.30, 0.06])
    let greenOnTMax = try await ratio("t-max-100", [0.06, 0.30, 0.06])
    #expect(greenOnTMax > greenOnTriX * 1.03)
    // MEM-248 expected a red target to be the clearest case and to run the other way.
    // It is neither. Through the digitised F-4017 and F-4016 spectral sensitivity
    // curves the two Stocks separate a red subject by well under one per cent, with
    // Tri-X very slightly the *lighter* — so this asserts what the datasheets give,
    // which is that red is where these two Stocks agree. Curves/tri-x-400/SOURCES.md
    // records the numbers; a red subject is still darker than a neutral on both.
    let redOnTriX = try await ratio("tri-x-400", [0.50, 0.06, 0.06])
    let redOnTMax = try await ratio("t-max-100", [0.50, 0.06, 0.06])
    #expect(redOnTriX >= redOnTMax)
    #expect(redOnTriX < redOnTMax * 1.01)
    #expect(redOnTriX < 0.95 && redOnTMax < 0.95)
}

@Test(arguments: ["tri-x-400", "t-max-100"])
func aContrastFilterMovesTonalSeparationAndNotExposure(id: String) async throws {
    let renderer = try Renderer()
    let profile = try stock(id)
    let sky: [Float16] = [0.10, 0.16, 0.42]
    let brick: [Float16] = [0.34, 0.14, 0.09]
    let grey: [Float16] = [0.18, 0.18, 0.18]
    var results: [ContrastFilter: [[Float]]] = [:]
    for filter in ContrastFilter.allCases {
        let result = try await render(renderer, [sky, brick, grey], profile: profile,
                                      settings: .init(output: .workingSpace, contrastFilter: filter))
        // The filter factor is applied with the filter, exactly as a photographer
        // meters without the glass and then opens up. Mid-grey does not move.
        for c in 0..<3 { #expect(abs(result[2][c] - 0.18) < 0.004, "\(filter) moved mid-grey") }
        // Nothing is tinted: a monochrome render is neutral whatever glass is on.
        #expect(result[0][0] == result[0][1] && result[0][1] == result[0][2])
        results[filter] = result
    }
    let none = try #require(results[.none])
    // Red darkens sky and lightens brick; blue does the reverse. Yellow and orange
    // sit between none and red, in that order, which is the whole point of owning
    // more than one piece of glass.
    let sky0 = { (f: ContrastFilter) in results[f]![0][0] }
    let brick0 = { (f: ContrastFilter) in results[f]![1][0] }
    #expect(sky0(.red) < sky0(.orange) && sky0(.orange) < sky0(.yellow) && sky0(.yellow) < sky0(.none))
    #expect(brick0(.red) > brick0(.orange) && brick0(.orange) > brick0(.yellow) && brick0(.yellow) > brick0(.none))
    #expect(sky0(.blue) > none[0][0] && brick0(.blue) < none[1][0])
    #expect(brick0(.green) < none[1][0])
    // A tint would move sky and brick the same way. A spectral multiply before the
    // collapse cannot: what one filter darkens, it lightens something else against.
    #expect(sky0(.red) < sky0(.none) && brick0(.red) > brick0(.none))
}

@Test func contrastFiltersBelongToTheBlackAndWhiteBranchAlone() async throws {
    let renderer = try Renderer()
    for id in ["portra-400", "study-c41", "study-e6"] {
        await #expect(throws: FilmError.self, "\(id) accepted a Contrast Filter") {
            _ = try await render(renderer, [[0.18, 0.18, 0.18]], profile: try stock(id),
                                 settings: .init(output: .workingSpace, contrastFilter: .red))
        }
        #expect(try stock(id).metadata.monochrome == nil)
    }
    // The synthetic studies are black & white but carry no measured sensitivity, so
    // they have no Contrast Filters to offer and say so rather than inventing one.
    let study = try stock("study-bw-silver")
    #expect(study.metadata.monochrome?.contrastFilters == nil)
    #expect(study.metadata.monochrome?.weight(for: .yellow) == nil)
    await #expect(throws: FilmError.self) {
        _ = try await render(renderer, [[0.18, 0.18, 0.18]], profile: study,
                             settings: .init(output: .workingSpace, contrastFilter: .yellow))
    }
    // The unfiltered collapse is always available, including on a study Profile.
    _ = try await render(renderer, [[0.18, 0.18, 0.18]], profile: study, settings: .init(output: .workingSpace))
}

@Test func derivedFilterFactorsAgreeWithThePublishedTables() throws {
    // Kodak publishes a daylight filter factor per Wratten filter per film, and the
    // two tables differ. Nothing in the model was fitted to them, so this is the
    // check that the Spectral Weights are each Stock's own.
    let published: [String: [ContrastFilter: Double]] = [
        "tri-x-400": [.yellow: 2, .orange: 2.5, .red: 8, .green: 6, .blue: 6],
        "t-max-100": [.yellow: 1.5, .orange: 2, .red: 8, .green: 6, .blue: 8],
    ]
    for (id, table) in published {
        let monochrome = try #require(try stock(id).metadata.monochrome)
        #expect(monochrome.filterFactorStops(.none) == 0)
        for (filter, factor) in table {
            let derived = try #require(monochrome.filterFactorStops(filter))
            #expect(abs(derived - log2(factor)) <= 0.7, "\(id) \(filter): \(derived) vs \(log2(factor)) stops")
            // Every filter subtracts light; none of them is close to free.
            #expect(derived > 0.5)
        }
    }
    // Red and green land on the published numbers; the residual is where the
    // artistic transmittance model is, not where the sensitivities are.
    for id in published.keys {
        let monochrome = try #require(try stock(id).metadata.monochrome)
        #expect(abs(try #require(monochrome.filterFactorStops(.red)) - 3) < 0.1)
        #expect(abs(try #require(monochrome.filterFactorStops(.green)) - log2(6)) < 0.1)
    }
}

@Test func aMonochromeProfileRejectsAnInvalidOrAuthoredCollapse() throws {
    let profile = try stock("tri-x-400")
    let payload = try ProfileContainer.decode(try ProfileContainer.encode(profile))
    let payloads = ["density.curve1d": Data(repeating: 0, count: 2048)]
    var invalid = payload.metadata
    invalid.monochrome?.spectralWeight = [-0.2, 0.6, 0.6]
    #expect(throws: (any Error).self) { try Profile(metadata: invalid, payloads: payloads) }
    invalid = payload.metadata
    invalid.monochrome?.spectralWeight = nil
    #expect(throws: (any Error).self) { try Profile(metadata: invalid, payloads: payloads) }
    invalid = payload.metadata
    invalid.monochrome?.contrastFilters?.removeLast()
    #expect(throws: (any Error).self) { try Profile(metadata: invalid, payloads: payloads) }
    invalid = payload.metadata
    invalid.provenance.removeValue(forKey: "monochrome.contrastFilters")
    #expect(throws: (any Error).self) { try Profile(metadata: invalid, payloads: payloads) }
    // A Colour Cube output has no meaning without a cube.
    invalid = payload.metadata
    invalid.colour.cubeOutput = .displayLinearRec2020
    #expect(throws: (any Error).self) { try Profile(metadata: invalid, payloads: payloads) }
    // A colour Stock cannot carry Contrast Filters, because it has no collapse.
    var colour = try stock("portra-400").metadata
    colour.monochrome = payload.metadata.monochrome
    #expect(throws: (any Error).self) { try Profile(metadata: colour, payloads: [:]) }
}
