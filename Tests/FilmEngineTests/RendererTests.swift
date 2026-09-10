import Testing
import Foundation
import FilmEngine

@Test func identityColourCubePreservesEveryFiniteHalfValue() async throws {
    let values = (0...UInt16.max).map { Float16(bitPattern: $0) }.filter { $0.isFinite }
    let pixels = values.flatMap { [$0, $0, $0, Float16(1)] }
    let image = try LinearImage(width: 256, height: values.count / 256, rgba: pixels)
    let renderer = try Renderer()
    let result = try await renderer.render(image: .linear(image), profile: .identity, settings: .init(output: .workingSpace))
    let mismatches = pixels.indices.filter { result.rgba[$0].bitPattern != pixels[$0].bitPattern }
    #expect(mismatches.isEmpty)
}

@Test func tetrahedraMatchAnalyticalMinimumAcrossAllSixOrderings() async throws {
    // At cube corners, pairwise products coincide with pairwise minima. Inside
    // each tetrahedron the affine extension is min(), unlike trilinear products.
    var texels: [Float16] = []
    for b in [Float16(0), 1] { for g in [Float16(0), 1] { for r in [Float16(0), 1] {
        texels += [r * g, g * b, r * b, 1]
    } } }
    let profile = Profile(colourCube: try ColourCube(size: 2, rgba: texels))
    let input: [Float16] = [0.75, 0.5, 0.25, 0.5, 0.75, 0.25, 0.5, 1,
        0.5, 0.75, 0.25, 1, 0.25, 0.75, 0.5, 1,
        0.5, 0.25, 0.75, 1, 0.25, 0.5, 0.75, 1]
    let expected: [Float16] = [0.5, 0.25, 0.25, 0.5, 0.25, 0.25, 0.5, 1,
        0.5, 0.25, 0.25, 1, 0.25, 0.5, 0.25, 1,
        0.25, 0.25, 0.5, 1, 0.25, 0.5, 0.25, 1]
    let renderer = try Renderer()
    let result = try await renderer.render(image: .linear(try LinearImage(width: 6, height: 1, rgba: input)),
        profile: profile, settings: .init(output: .workingSpace))
    #expect(result.rgba == expected)
}

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@Test func taggedPhotosUseTheirOwnPrimaries() async throws {
    let renderer = try Renderer()
    var results: [[Float16]] = []
    for name in [CGColorSpace.sRGB, CGColorSpace.displayP3] {
        let data = NSMutableData()
        let provider = CGDataProvider(data: Data([255, 0, 0, 255]) as CFData)!
        let image = CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
            space: CGColorSpace(name: name)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .relativeColorimetric)!
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let result = try await renderer.render(image: .encoded(data as Data), profile: .identity, settings: .init(output: .workingSpace))
        results.append(result.rgba)
    }
    // Independently derived primary conversion matrices, tolerance includes ICC quantisation.
    for (actual, expected) in zip(results[0], [0.6274, 0.0691, 0.0164, 1.0]) {
        #expect(abs(Double(actual) - expected) < 0.002)
    }
    for (actual, expected) in zip(results[1], [0.7538, 0.0457, -0.0012, 1.0]) {
        #expect(abs(Double(actual) - expected) < 0.002)
    }
}

@Test func rawDecodePreservesSceneLinearExposureRatios() async throws {
    let directory = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    let renderer = try Renderer()
    var samples: [[Float16]] = []
    for name in ["linear-low", "linear-high"] {
        let data = try Data(contentsOf: directory.appendingPathComponent(name + ".dng"))
        let result = try await renderer.render(image: .encoded(data), profile: .identity, settings: .init(output: .workingSpace))
        let center = (result.height / 2 * result.width + result.width / 2) * 4
        samples.append(Array(result.rgba[center..<(center + 3)]))
    }
    for channel in 0..<3 {
        #expect(samples[0][channel] > 0)
        #expect(abs(Float(samples[1][channel]) / Float(samples[0][channel]) - 2) < 0.01)
    }
}

@Test func untaggedInputDoesNotSilentlyAssumeSRGB() async throws {
    let url = try #require(Bundle.module.url(forResource: "untagged", withExtension: "png", subdirectory: "Fixtures"))
    let data = try Data(contentsOf: url)
    let renderer = try Renderer()
    await #expect(throws: FilmError.self) { _ = try await renderer.render(image: .encoded(data), profile: .identity) }
}

/// Reused ping-pong textures must be refilled, and resizing must discard both.
@Test func repeatedPreviewRendersMatchFreshRenderers() async throws {
    let renderer = try Renderer()
    for (width, exposure) in [(32, 1.0), (32, 0.0), (17, -1.0), (32, 0.5)] {
        let image = try LinearImage(width: width, height: 13,
                                    rgba: Array(repeating: [Float16(0.2), 0.4, 0.6, 1], count: width * 13).flatMap { $0 })
        let settings = RenderSettings(output: .workingSpace, exposureStops: exposure)
        let actual = try await renderer.render(image: .linear(image), profile: .identity, settings: settings)
        let fresh = try Renderer()
        let expected = try await fresh.render(image: .linear(image), profile: .identity, settings: settings)
        #expect(actual.width == width)
        #expect(actual.rgba == expected.rgba)
        #expect(actual.id != expected.id)
        let copy = actual
        #expect(copy.id == actual.id)
    }
}
