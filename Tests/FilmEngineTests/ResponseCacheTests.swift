import Testing
import Foundation
import FilmEngine

// The Colour Cube cache, asserted through the renderer seam and through the one thing
// a cache leaves behind that pixels do not: whether the Profile was read again.

private func reference(_ size: Int = 96) throws -> LinearImage {
    var rgba = [Float16](repeating: 0, count: size * size * 4)
    for y in 0..<size {
        for x in 0..<size {
            let index = (y * size + x) * 4
            rgba[index] = Float16(Double(x) / Double(size - 1))
            rgba[index + 1] = Float16(Double(y) / Double(size - 1))
            rgba[index + 2] = 0.18
            rgba[index + 3] = 1
        }
    }
    return try LinearImage(width: size, height: size, rgba: rgba)
}

@Test func aSecondCatalogueSweepReadsNoProfilePayloadAtAll() async throws {
    // The filmstrip renders the whole Catalogue after a settings change, the Contact
    // Sheet renders it on every open, and the Preset sheet renders a row of it. With
    // a cache too small to hold one sweep none of that is ever reused: each surface
    // pays the full read, decode and upload every time it appears.
    let renderer = try Renderer()
    let catalogue = try ProfileCatalogue.bundled().profiles
    let image = try reference()
    for profile in catalogue {
        _ = try await renderer.render(image: .linear(image), profile: profile, settings: .init())
    }
    let afterFirst = catalogue.map(\.payloadReads)
    #expect(afterFirst.allSatisfy { $0 > 0 })
    for profile in catalogue {
        _ = try await renderer.render(image: .linear(image), profile: profile, settings: .init())
    }
    for (profile, first) in zip(catalogue, afterFirst) {
        #expect(profile.payloadReads == first, "\(profile.id) re-read its payloads")
    }
    #expect(await renderer.retainedResponseBytes <= 96 << 20)
}

@Test func aPlanNeverEvictsTheColourCubesItIsBeingBuiltFrom() async throws {
    // A single Plan can ask for four cubes at once: lower and upper Film Response for
    // a fractional Development Offset, and the lower and upper Output Stage cubes that
    // go with them. Against a budget too small to hold all four, an eviction policy
    // that did not pin them would hand the Plan a released texture — and the render
    // would either differ or crash, rather than merely being slower.
    let profile = try #require(ProfileCatalogue.bundled().profiles.first { $0.id == "portra-400" })
    let image = try reference()
    // Half a stop, so neither variant is exact and both ends of the blend are live.
    let settings = RenderSettings(developmentOffset: 0.5, outputStage: .print)
    let generous = try Renderer(responseCacheBudgetBytes: 96 << 20)
    let tight = try Renderer(responseCacheBudgetBytes: 16 << 20)
    let expected = try await generous.render(image: .linear(image), profile: profile, settings: settings)
    let squeezed = try await tight.render(image: .linear(image), profile: profile, settings: settings)
    #expect(expected.rgba == squeezed.rgba)
}

@Test func theColourCubeBudgetIsCountedInBytesRatherThanEntries() async throws {
    // Cinestill's cube is 129³ where every other Stock's is 65³ — eight times the read,
    // the decode and the upload. A cache counted in entries cannot know that, so four
    // entries is anywhere between 8KB and 65MB depending on which four they are.
    let renderer = try Renderer(responseCacheBudgetBytes: 20 << 20)
    let catalogue = try ProfileCatalogue.bundled().profiles
    let image = try reference()
    for profile in catalogue {
        _ = try await renderer.render(image: .linear(image), profile: profile, settings: .init())
        #expect(await renderer.retainedResponseBytes <= 20 << 20)
    }
    // And a budget too small to hold the Catalogue is a slower render, never a wrong
    // one: every Profile still renders.
    #expect(await renderer.retainedResponseBytes > 0)
}

@Test func releasingTheCachesCostsTheReadingRatherThanTheResult() async throws {
    let renderer = try Renderer()
    let profile = try #require(ProfileCatalogue.bundled().profiles.first { $0.id == "portra-400" })
    let image = try reference()
    let settings = RenderSettings(halationIntensity: 1)
    let before = try await renderer.render(image: .linear(image), profile: profile, settings: settings)
    #expect(await renderer.retainedResponseBytes > 0)
    await renderer.releaseCaches()
    #expect(await renderer.retainedResponseBytes == 0)
    #expect(await renderer.retainedTileTextureBytes == 0)
    let after = try await renderer.render(image: .linear(image), profile: profile, settings: settings)
    #expect(before.rgba == after.rgba)
}

@Test func concurrentRendersOnOneRendererMatchTheirSequentialEquivalents() async throws {
    // The renderer no longer holds its actor for the duration of a GPU pass, which
    // makes the actor reentrant at exactly the moment the ping-pong pair, the
    // Scattering Pyramid and the MTF textures are live. A second render entering there
    // would reallocate or overwrite them under the first.
    let catalogue = try ProfileCatalogue.bundled().profiles
    let portra = try #require(catalogue.first { $0.id == "portra-400" })
    let cinestill = try #require(catalogue.first { $0.id == "cinestill-800t" })
    // Different dimensions as well as different Profiles: the textures are keyed by
    // size, so two renders that disagree about the size are the case that reallocates.
    let jobs: [(Profile, LinearImage, RenderSettings)] = [
        (portra, try reference(96), RenderSettings(halationIntensity: 1)),
        (cinestill, try reference(64), RenderSettings(temperatureKelvin: 3200, halationIntensity: 2)),
        (portra, try reference(128), RenderSettings(exposureStops: 1)),
        (cinestill, try reference(96), RenderSettings(temperatureKelvin: 3200, bloomIntensity: 2)),
    ]
    let alone = try Renderer()
    var sequential: [RenderedPixels] = []
    for (profile, image, settings) in jobs {
        sequential.append(try await alone.render(image: .linear(image), profile: profile, settings: settings))
    }

    let shared = try Renderer()
    let concurrent = try await withThrowingTaskGroup(of: (Int, RenderedPixels).self) { group in
        for (index, job) in jobs.enumerated() {
            group.addTask { (index, try await shared.render(image: .linear(job.1), profile: job.0, settings: job.2)) }
        }
        var results = [RenderedPixels?](repeating: nil, count: jobs.count)
        for try await (index, pixels) in group { results[index] = pixels }
        return results.compactMap { $0 }
    }
    #expect(concurrent.count == jobs.count)
    for (expected, actual) in zip(sequential, concurrent) {
        #expect(expected.width == actual.width && expected.height == actual.height)
        #expect(expected.rgba == actual.rgba)
    }
}

@Test func aPreviewRenderDoesNotWaitOutAnExport() async throws {
    // The Export path and the Preview path stop sharing one Renderer's scratch, so an
    // Export in flight is not a Preview that has to wait for it. Both complete, and
    // both are what they would have been alone.
    let profile = try #require(ProfileCatalogue.bundled().profiles.first { $0.id == "portra-400" })
    let previewImage = try reference(128)
    let exportImage = try reference(192)
    let settings = RenderSettings(halationIntensity: 1)
    let options = ExportOptions(textureBudgetBytes: 64 * 64 * 8 * TilePlan.tileTextureCount,
                                minimumTileEdge: 16, thermalState: .nominal)
    let alone = try await Renderer().render(image: .linear(previewImage), profile: profile, settings: settings)

    let previewRenderer = try Renderer()
    let exportRenderer = try Renderer()
    async let exported = exportRenderer.export(image: .linear(exportImage), profile: profile,
                                               settings: settings, format: .jpeg, options: options)
    async let preview = previewRenderer.render(image: .linear(previewImage), profile: profile, settings: settings)
    let (file, pixels) = try await (exported, preview)
    #expect(!file.isEmpty)
    #expect(pixels.rgba == alone.rgba)
}
