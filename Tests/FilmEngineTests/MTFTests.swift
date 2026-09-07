import Testing
import Foundation
import FilmEngine

/// An identity Colour Cube isolates the MTF Pass: what comes back is the Stock's
/// spatial response applied to the grating, not the Film Response's reading of it.
private func responding(cyclesPerMM: [Double], response: [Double]) throws -> Profile {
    var metadata = Profile.identity.metadata
    metadata.mtf = FilmProfile.MTF(cyclesPerMM: cyclesPerMM, response: response)
    return try Profile(metadata: metadata, payloads: ["identity.lut3d": ColourCube.identity.payload])
}

/// A sinusoidal grating at a stated frequency on the film, which is what a published
/// MTF is measured with. Its mean sits at mid-grey so nothing clips either way.
private func grating(width: Int, height: Int, cyclesPerMM: Double, frameWidthMM: Double = 36) throws -> LinearImage {
    let cyclesPerPixel = cyclesPerMM * frameWidthMM / Double(max(width, height))
    var rgba = [Float16](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let value = Float16(0.5 + 0.25 * sin(2 * .pi * cyclesPerPixel * (Double(x) + 0.5)))
            for c in 0..<3 { rgba[(y * width + x) * 4 + c] = value }
            rgba[(y * width + x) * 4 + 3] = 1
        }
    }
    return try LinearImage(width: width, height: height, rgba: rgba)
}

/// The grating's amplitude, projected onto the frequency it was drawn at. Edge
/// columns are dropped because the blur clamps there rather than wrapping.
private func modulation(_ pixels: [Float16], width: Int, height: Int, cyclesPerMM: Double, frameWidthMM: Double = 36) -> Double {
    let cyclesPerPixel = cyclesPerMM * frameWidthMM / Double(max(width, height))
    let margin = width / 8
    var sine = 0.0, cosine = 0.0, count = 0.0
    for y in 0..<height {
        for x in margin..<(width - margin) {
            let phase = 2 * .pi * cyclesPerPixel * (Double(x) + 0.5)
            let value = Double(pixels[(y * width + x) * 4])
            sine += value * sin(phase)
            cosine += value * cos(phase)
            count += 1
        }
    }
    return 2 * (sine * sine + cosine * cosine).squareRoot() / count
}

@Test func theMTFPassReproducesTheProfilesPublishedResponseCurve() async throws {
    // A Gaussian response in cycles per millimetre, sampled the way a datasheet
    // samples one. At 1024 pixels across a 36 mm frame, Nyquist is 14 cycles/mm.
    let sigmaMM = 0.03
    let cycles = [2.0, 4, 6, 8, 10, 12]
    let published = cycles.map { exp(-2 * .pi * .pi * sigmaMM * sigmaMM * $0 * $0) }
    let profile = try responding(cyclesPerMM: cycles, response: published)
    let renderer = try Renderer()
    for (frequency, expected) in zip(cycles, published) {
        let image = try grating(width: 1024, height: 64, cyclesPerMM: frequency)
        let result = try await renderer.render(image: .linear(image), profile: profile, settings: .init(output: .workingSpace))
        let rendered = modulation(result.rgba, width: 1024, height: 64, cyclesPerMM: frequency)
        #expect(abs(rendered / 0.25 - expected) < 0.05)
    }
}

@Test func aStocksPublishedAdjacencyEffectRaisesMicroContrast() async throws {
    // Portra's measured curve sits above one below about 20 cycles/mm — the
    // adjacency effect of development, not a digitising error — so the Pass has to
    // be able to raise micro-contrast rather than only lose it.
    let portra = try #require(ProfileCatalogue.bundled().profiles.first { $0.id == "portra-400" })
    let published = zip(portra.metadata.mtf.cyclesPerMM, portra.metadata.mtf.response)
    #expect(published.contains { $0.0 <= 10 && $0.1 > 1.05 })
    // Read through the identity cube: the Film Response is not what is under test.
    var metadata = Profile.identity.metadata
    metadata.mtf = portra.metadata.mtf
    let profile = try Profile(metadata: metadata, payloads: ["identity.lut3d": ColourCube.identity.payload])
    let renderer = try Renderer()
    for (frequency, expected) in zip([5.0, 10], [1.088, 1.166]) {
        let image = try grating(width: 1024, height: 64, cyclesPerMM: frequency)
        let result = try await renderer.render(image: .linear(image), profile: profile, settings: .init(output: .workingSpace))
        let rendered = modulation(result.rgba, width: 1024, height: 64, cyclesPerMM: frequency) / 0.25
        #expect(rendered > 1.02)
        #expect(abs(rendered - expected) < 0.08)
    }
}

@Test func theMTFPassIsFixedToTheFrameRatherThanToThePixelGrid() async throws {
    // The same frequency on the film is the same fraction of the frame at any size,
    // so it must lose the same contrast at both — the pixel period differs by four.
    let profile = try responding(cyclesPerMM: [2, 4, 6, 8, 10, 12],
                                 response: [0.97, 0.88, 0.75, 0.61, 0.47, 0.35])
    let renderer = try Renderer()
    var rendered: [Double] = []
    for size in [1024, 4096] {
        let image = try grating(width: size, height: 16, cyclesPerMM: 6)
        let result = try await renderer.render(image: .linear(image), profile: profile, settings: .init(output: .workingSpace))
        rendered.append(modulation(result.rgba, width: size, height: 16, cyclesPerMM: 6) / 0.25)
    }
    #expect(abs(rendered[0] - 0.75) < 0.05)
    #expect(abs(rendered[0] - rendered[1]) < 0.05)
}

@Test func aFlatOrUnresolvableMTFLeavesTheFrameUntouched() async throws {
    let renderer = try Renderer()
    // The identity Profile is the calibration seam: no film, so no spatial response.
    let image = try grating(width: 512, height: 16, cyclesPerMM: 6)
    let flat = try await renderer.render(image: .linear(image), profile: .identity, settings: .init(output: .workingSpace))
    #expect(flat.rgba == image.rgba)
    // A 128-pixel frame carries 3.5 cycles/mm at Nyquist, so a curve published from
    // 5 cycles/mm upward says nothing about it and the Pass does not run.
    let small = try grating(width: 128, height: 8, cyclesPerMM: 1)
    let profile = try responding(cyclesPerMM: [5, 10, 20, 40, 80], response: [1, 0.98, 0.82, 0.51, 0.19])
    let unresolvable = try await renderer.render(image: .linear(small), profile: profile, settings: .init(output: .workingSpace))
    #expect(unresolvable.rgba == small.rgba)
}
