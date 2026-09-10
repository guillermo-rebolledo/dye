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
        // Recorded rather than expected: `#expect` on two 192 KB payloads spends ten
        // minutes formatting operands it then elides anyway, and a Golden Image that
        // has moved is exactly when nobody wants to wait. The comparison is the same
        // bit-exact one; only the reporting is cheap.
        if bytes != expected {
            let failures = directory.deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(".build/golden-failures")
            try FileManager.default.createDirectory(at: failures, withIntermediateDirectories: true)
            try bytes.write(to: failures.appendingPathComponent("\(profile.id).actual.rgba16"), options: .atomic)
            try expected.write(to: failures.appendingPathComponent("\(profile.id).expected.rgba16"), options: .atomic)
            let offset = zip(bytes, expected).enumerated().first { $0.element.0 != $0.element.1 }?.offset
            let site = offset.map { "first differs at byte \($0) of \(expected.count)" } ?? "lengths differ"
            let advice = "Review the Contact Sheet and follow docs/golden-images.md; never update automatically."
            Issue.record("Golden Image changed: \(profile.id), \(site). \(advice)")
        }
    }
}
