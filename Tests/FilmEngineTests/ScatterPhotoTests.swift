import Testing
import FilmEngine

/// A bright wall beside a dark subject, within an ordinary decoded photo's 0...1
/// range. HDR point lights alone cannot catch controls that do nothing on SDR.
@Test func boostedScatteringIsVisibleOnSDRPhotoEdges() async throws {
    let renderer = try Renderer()
    let profile = try #require(ProfileCatalogue.bundled().profiles.first { $0.id == "portra-400" })
    let size = 512
    var rgba = [Float16](repeating: 1, count: size * size * 4)
    for y in 0..<size {
        for x in 0..<size {
            for c in 0..<3 { rgba[(y * size + x) * 4 + c] = x < size / 2 ? 0.08 : 0.85 }
        }
    }
    let image = try LinearImage(width: size, height: size, rgba: rgba)
    func render(bloom: Double, halation: Double) async throws -> [Float16] {
        try await renderer.render(image: .linear(image), profile: profile,
                                  settings: .init(halationIntensity: halation, bloomIntensity: bloom,
                                                  grainIntensity: 0)).rgba
    }
    let off = try await render(bloom: 0, halation: 0)
    let bloom = try await render(bloom: 2, halation: 0)
    let halo = try await render(bloom: 0, halation: 2)
    let normal = try await render(bloom: 0, halation: 1)
    let intermediate = try await render(bloom: 0, halation: 1.5)
    let intermediateBloom = try await render(bloom: 1.5, halation: 0)
    let edge = (size / 2 * size + size / 2 - 2) * 4
    // More than several display code values, individually, with the real stock's
    // response enabled. Halation must favour red at the dark side of the edge.
    #expect(Double(bloom[edge] - off[edge]) > 0.025)
    #expect(Double(halo[edge] - off[edge]) > 0.025)
    #expect(halo[edge] - off[edge] > halo[edge + 1] - off[edge + 1])
    #expect(halo[edge] > intermediate[edge])
    #expect(intermediate[edge] > normal[edge])
    #expect(bloom[edge] > intermediateBloom[edge])
    // Away from the bright edge, halation must leave the dark field alone.
    let dark = (size / 2 * size + 64) * 4
    #expect(abs(Double(halo[dark] - off[dark])) < 0.002)
}

/// Every catalogue entry, including Identity and zero-strength monochrome stocks,
/// must offer working scattering without changing its default rendering.
@Test func creativeScatteringWorksAcrossTheCatalogueAndWithoutStock() async throws {
    let renderer = try Renderer()
    let profiles = try [Profile.identity] + ProfileCatalogue.bundled().profiles
    let size = 128
    var rgba = [Float16](repeating: 1, count: size * size * 4)
    for y in 0..<size {
        for x in 0..<size {
            for c in 0..<3 { rgba[(y * size + x) * 4 + c] = x < size / 2 ? 0.08 : 0.85 }
        }
    }
    let image = try LinearImage(width: size, height: size, rgba: rgba)
    let edge = (size / 2 * size + size / 2 - 1) * 4
    for profile in profiles {
        func render(bloom: Double, halation: Double) async throws -> [Float16] {
            try await renderer.render(image: .linear(image), profile: profile,
                                      settings: .init(output: .workingSpace,
                                                      halationIntensity: halation,
                                                      bloomIntensity: bloom, grainIntensity: 0)).rgba
        }
        let off = try await render(bloom: 0, halation: 0)
        for isBloom in [true, false] {
            let boosted = try await render(bloom: isBloom ? 2 : 0, halation: isBloom ? 0 : 2)
            let intermediate = try await render(bloom: isBloom ? 1.5 : 0, halation: isBloom ? 0 : 1.5)
            #expect(boosted[edge] > intermediate[edge], "\(profile.id): bloom=\(isBloom)")
            // Native stock thresholds can still exclude SDR highlights at 150%.
            #expect(boosted[edge] > off[edge], "\(profile.id): bloom=\(isBloom)")
            let strength = isBloom ? profile.metadata.bloom.strength : profile.metadata.halation.strength
            if strength == 0 {
                #expect(intermediate[edge] > off[edge], "\(profile.id): creative fallback")
                for intensity in [0.5, 1.0] {
                    let baseline = try await render(bloom: isBloom ? intensity : 0,
                                                    halation: isBloom ? 0 : intensity)
                    #expect(baseline == off, "\(profile.id): neutral baseline")
                }
            }
        }
    }
}
