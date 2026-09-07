import Testing
import Foundation
import FilmEngine

/// An identity Colour Cube isolates the Grain Pass: the Density Space signal is the
/// input itself, so whatever comes back is the fluctuation the Pass added.
private func graining(radiusMicrons: Double, rms: Double = 0.05, correlation: Double = 0,
                      radiusScale: [Double] = [1, 1, 1], response: [Double]? = nil,
                      outputStage: OutputStage = .none) throws -> Profile {
    var metadata = Profile.identity.metadata
    // Reversal film is the final image, so only a negative Stock has an Output Stage.
    metadata.process = .c41
    metadata.colour.outputStage = outputStage
    // A triangle peaking at mid-density: loud in the midtones, silent at both ends.
    let triangle: [Double] = (0..<32).map { index in 1 - abs(Double(index) - 15.5) / 15.5 }
    let densityResponse = response ?? triangle
    metadata.grain = FilmProfile.Grain(model: .procedural, rmsGranularity: rms, grainRadiusMicrons: radiusMicrons,
                                       densityResponse: densityResponse, channelCorrelation: correlation,
                                       channelRadiusScale: radiusScale)
    return try Profile(metadata: metadata, payloads: ["identity.lut3d": ColourCube.identity.payload])
}

private func flat(width: Int, height: Int, value: Float16) throws -> LinearImage {
    var rgba = [Float16](repeating: value, count: width * height * 4)
    for i in stride(from: 3, to: rgba.count, by: 4) { rgba[i] = 1 }
    return try LinearImage(width: width, height: height, rgba: rgba)
}

/// The Grain Pass's own contribution: the same render with and without it.
private func grainField(_ renderer: Renderer, profile: Profile, image: LinearImage,
                        channel: Int = 0, settings: RenderSettings = .init(output: .workingSpace)) async throws -> [Double] {
    var without = settings
    without.grainIntensity = 0
    let grainy = try await renderer.render(image: .linear(image), profile: profile, settings: settings)
    let plain = try await renderer.render(image: .linear(image), profile: profile, settings: without)
    return (0..<(image.width * image.height)).map { Double(grainy.rgba[$0 * 4 + channel]) - Double(plain.rgba[$0 * 4 + channel]) }
}

private func deviation(_ values: [Double]) -> Double {
    let mean = values.reduce(0, +) / Double(values.count)
    return (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
}

/// The lag, as a fraction of the frame's long edge, at which the field decorrelates
/// to half. This is the number that must not move with output resolution.
private func correlationLength(_ field: [Double], width: Int, height: Int) -> Double {
    let mean = field.reduce(0, +) / Double(field.count)
    let centred = field.map { $0 - mean }
    let rows = stride(from: 0, to: height, by: 4)
    let limit = width / 8
    func correlation(lag: Int) -> Double {
        var product = 0.0, energy = 0.0
        for y in rows {
            for x in 0..<(width - limit) {
                product += centred[y * width + x] * centred[y * width + x + lag]
                energy += centred[y * width + x] * centred[y * width + x]
            }
        }
        return energy > 0 ? product / energy : 0
    }
    var previous = 1.0
    for lag in 1...limit {
        let value = correlation(lag: lag)
        // Interpolate between the bracketing lags so the length is not quantised to
        // whole pixels, which would hide a real drift at the smallest size.
        if value < 0.5 { return (Double(lag - 1) + (previous - 0.5) / (previous - value)) / Double(max(width, height)) }
        previous = value
    }
    return 1
}

@Test func grainIsTheSameSizeRelativeToTheFrameAtEveryOutputResolution() async throws {
    // 500 µm crystals are far coarser than any real Emulsion, which is the point:
    // the field has to be resolvable at test sizes for its size to be measurable.
    let renderer = try Renderer()
    let profile = try graining(radiusMicrons: 500)
    var lengths: [Double] = []
    for size in [512, 1024, 2048] {
        let field = try await grainField(renderer, profile: profile, image: try flat(width: size, height: size, value: 0.18))
        lengths.append(correlationLength(field, width: size, height: size))
    }
    for length in lengths { #expect(abs(length - lengths[0]) < 0.1 * lengths[0]) }
    // The size comes from the Profile: crystals twice as wide decorrelate twice as far.
    let finer = try await grainField(renderer, profile: try graining(radiusMicrons: 250),
                                     image: try flat(width: 1024, height: 1024, value: 0.18))
    #expect(abs(correlationLength(finer, width: 1024, height: 1024) / lengths[1] - 0.5) < 0.05)
    // Frame Width is the frame's long edge, so a portrait frame grains as a landscape one.
    let landscape = try await grainField(renderer, profile: profile, image: try flat(width: 1024, height: 512, value: 0.18))
    let portrait = try await grainField(renderer, profile: profile, image: try flat(width: 512, height: 1024, value: 0.18))
    #expect(abs(correlationLength(landscape, width: 1024, height: 512)
                - correlationLength(portrait, width: 1024, height: 512)) < 0.005)
}

@Test func grainFinerThanAPixelIsCarriedByItsAmplitudeRatherThanItsSize() async throws {
    // The regime every shipped Stock is actually in: 1.2 µm crystals on a 36 mm frame
    // would need 30 000 pixels to resolve, so the cell floors at one pixel at every
    // practical size and Selwyn's law carries the published granularity instead.
    // Halve the pixel pitch and the fluctuation the frame records doubles.
    let renderer = try Renderer()
    let profile = try graining(radiusMicrons: 1.2, rms: 0.02)
    var deviations: [Double] = []
    for size in [256, 512, 1024] {
        let field = try await grainField(renderer, profile: profile, image: try flat(width: size, height: size, value: 0.18))
        deviations.append(deviation(field))
        // One pixel holds one independent sample: neighbours share no crystals.
        let neighbours = (0..<(size * (size - 1))).map { field[$0] * field[$0 + 1] }.reduce(0, +) / Double(size * (size - 1))
        #expect(abs(neighbours) < 0.05 * deviations.last! * deviations.last!)
    }
    for (coarser, finer) in zip(deviations, deviations.dropFirst()) { #expect(abs(finer / coarser - 2) < 0.05) }
    // The published figure is measured through a 48 µm aperture, and one pixel of a
    // 256-pixel frame across 36 mm is 141 µm of it.
    #expect(abs(deviations[0] / (0.02 * 48 / 140.625) - 1) < 0.05)
}

@Test func grainAmplitudeFollowsTheDensityResponseAndTheIntensityControl() async throws {
    let renderer = try Renderer()
    let profile = try graining(radiusMicrons: 500)
    let image = try flat(width: 256, height: 256, value: 0.18)
    // Zero intensity is not a quiet Pass but no Pass: the frame is untouched.
    let off = try await renderer.render(image: .linear(image), profile: profile,
                                        settings: .init(output: .workingSpace, grainIntensity: 0))
    #expect(off.rgba == image.rgba)
    let stock = deviation(try await grainField(renderer, profile: profile, image: image))
    let doubled = deviation(try await grainField(renderer, profile: profile, image: image,
                                                 settings: .init(output: .workingSpace, grainIntensity: 2)))
    #expect(abs(doubled / stock - 2) < 0.02)
    // Mid-grey sits at the peak of the Density Response; base and twice mid-grey are
    // its two ends, where an Emulsion has nothing left to fluctuate.
    let shadow = deviation(try await grainField(renderer, profile: profile, image: try flat(width: 256, height: 256, value: 0.002)))
    let highlight = deviation(try await grainField(renderer, profile: profile, image: try flat(width: 256, height: 256, value: 0.36)))
    #expect(shadow < stock / 10)
    #expect(highlight < stock / 10)
    let quarter = deviation(try await grainField(renderer, profile: profile, image: try flat(width: 256, height: 256, value: 0.09)))
    #expect(quarter > shadow && quarter < stock)
}

@Test func channelCorrelationDecidesHowFarTheThreeLayersGrainTogether() async throws {
    let renderer = try Renderer()
    let image = try flat(width: 256, height: 256, value: 0.18)
    func crossCorrelation(_ correlation: Double) async throws -> Double {
        let profile = try graining(radiusMicrons: 500, correlation: correlation)
        let red = try await grainField(renderer, profile: profile, image: image, channel: 0)
        let green = try await grainField(renderer, profile: profile, image: image, channel: 1)
        let product = zip(red, green).map(*).reduce(0, +) / Double(red.count)
        return product / (deviation(red) * deviation(green))
    }
    // C-41 layers grain independently; a silver Stock's single layer grains as one.
    #expect(try await crossCorrelation(0) < 0.05)
    #expect(try await abs(crossCorrelation(1) - 1) < 0.02)
    #expect(try await abs(crossCorrelation(0.5) - 0.5) < 0.05)
}

@Test func grainIsAppliedInDensitySpaceBeforeTheOutputStage() async throws {
    // The Scan inverts and compresses density, so grain that precedes it arrives at
    // the output multiplied by the Scan's own slope. Grain added afterwards would
    // arrive at its Density Space amplitude instead. High density is where the two
    // part company: the Scan's shoulder is flat there and passes less than half of
    // the fluctuation on, where near mid-grey it happens to pass almost all of it.
    let renderer = try Renderer()
    let flatResponse = [Double](repeating: 1, count: 32)
    let profile = try graining(radiusMicrons: 1.2, rms: 0.04, response: flatResponse, outputStage: .scan)
    let density = 1.0
    let measured = deviation(try await grainField(renderer, profile: profile,
                                                  image: try flat(width: 256, height: 256, value: Float16(density))))
    // The Scan's slope at that density, regressed from a short wedge read back
    // through the same public entry point rather than assumed from the shader.
    let densities = (-6...6).map { density + Double($0) * 0.01 }
    let wedge = try LinearImage(width: densities.count, height: 1,
                                rgba: densities.flatMap { [Float16($0), Float16($0), Float16($0), 1] })
    let scanned = try await renderer.render(image: .linear(wedge), profile: profile,
                                            settings: .init(output: .workingSpace, grainIntensity: 0))
    let meanX = densities.reduce(0, +) / Double(densities.count)
    let outputs = densities.indices.map { Double(scanned.rgba[$0 * 4]) }
    let meanY = outputs.reduce(0, +) / Double(outputs.count)
    let covariance: Double = zip(densities, outputs).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
    let variance: Double = densities.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
    let slope = covariance / variance
    let inDensitySpace = deviation(try await grainField(renderer, profile: try graining(radiusMicrons: 1.2, rms: 0.04, response: flatResponse),
                                                        image: try flat(width: 256, height: 256, value: Float16(density))))
    #expect(abs(measured / (slope * inDensitySpace) - 1) < 0.08)
    #expect(abs(measured / inDensitySpace - 1) > 0.5)
}

@Test func grainIntensityIsAZeroToTwoHundredPercentControl() async throws {
    let renderer = try Renderer()
    let image = try flat(width: 8, height: 8, value: 0.18)
    for intensity in [-0.01, 2.01, Double.nan] {
        await #expect(throws: FilmError.self) {
            _ = try await renderer.render(image: .linear(image), profile: .identity,
                                          settings: .init(output: .workingSpace, grainIntensity: intensity))
        }
    }
    // The default is the Stock's own granularity rather than an invented number.
    #expect(RenderSettings().grainIntensity == 1)
    #expect(RenderSettings.grainRange == 0...2)
}

@Test func theSeedFixesTheGrainFieldWithoutChangingItsAmplitude() async throws {
    let renderer = try Renderer()
    let profile = try graining(radiusMicrons: 500)
    let image = try flat(width: 128, height: 128, value: 0.18)
    let first = try await grainField(renderer, profile: profile, image: image)
    let repeated = try await grainField(renderer, profile: profile, image: image)
    let reseeded = try await grainField(renderer, profile: profile, image: image,
                                        settings: .init(output: .workingSpace, seed: 7))
    #expect(first == repeated)
    #expect(first != reseeded)
    #expect(abs(deviation(reseeded) / deviation(first) - 1) < 0.1)
}
