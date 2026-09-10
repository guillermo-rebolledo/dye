import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import FilmEngine

/// Opt-in diagnostic, not a portable performance gate.
@Test(.enabled(if: ProcessInfo.processInfo.environment["DYE_PHOTO_OPEN_AUDIT"] == "1"))
@MainActor func photoOpenAudit() async throws {
    func milliseconds(_ start: ContinuousClock.Instant) -> Double {
        let c = (ContinuousClock.now - start).components
        return Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
    }
    let context = try #require(CGContext(data: nil, width: 4032, height: 3024,
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.displayP3)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 4032, height: 3024))
    let image = try #require(context.makeImage())
    let encoded = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(encoded, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    let data = encoded as Data
    let catalogueStart = ContinuousClock.now
    let catalogue = try ProfileCatalogue.bundled()
    print("PHOTO_AUDIT catalogue_ms=\(milliseconds(catalogueStart)) profiles=\(catalogue.profiles.count)")
    for iteration in 1...3 {
        let total = ContinuousClock.now
        var start = ContinuousClock.now
        let renderer = try Renderer()
        let initialization = milliseconds(start)
        start = .now
        let preview = try await renderer.decode(data, maximumDimension: 2048)
        let decode = milliseconds(start)
        start = .now
        _ = try await renderer.render(image: .linear(preview), profile: .identity)
        let before = milliseconds(start)
        start = .now
        _ = try await renderer.decode(data, maximumDimension: 192)
        let thumbnail = milliseconds(start)
        start = .now
        _ = try await renderer.render(image: .linear(preview), profile: .identity)
        let edited = milliseconds(start)
        print("PHOTO_AUDIT iteration=\(iteration) init_main_actor_ms=\(initialization) preview_decode_ms=\(decode) before_ms=\(before) thumbnail_decode_ms=\(thumbnail) edited_ms=\(edited) total_ms=\(milliseconds(total))")
    }
}
