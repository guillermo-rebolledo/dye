import Foundation
import Testing
import FilmEngine

@Test func catalogueRendersMatchGoldenImages() async throws {
    let renderer = try Renderer()
    let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/GoldenImages")
    let recording = ProcessInfo.processInfo.environment["DYE_RECORD_GOLDENS"] == "1"
    for profile in try ProfileCatalogue.bundled().profiles {
        let pixels = try await renderer.render(image: .linear(ContactSheetReference.image()),
                                               profile: profile, settings: ContactSheetReference.settings)
        // Explicit little-endian float16 bits: no image encoder, tolerance, or SDR clipping.
        let bytes = Data(pixels.rgba.flatMap { [UInt8(truncatingIfNeeded: $0.bitPattern), UInt8($0.bitPattern >> 8)] })
        let url = directory.appendingPathComponent("\(profile.id).rgba16")
        if recording { try bytes.write(to: url, options: .atomic) }
        let expected = try Data(contentsOf: url)
        #expect(bytes == expected, "Golden Image changed: \(profile.id). Review the Contact Sheet and follow docs/golden-images.md; never update automatically.")
    }
}
