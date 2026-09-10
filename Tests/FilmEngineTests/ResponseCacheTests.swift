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
