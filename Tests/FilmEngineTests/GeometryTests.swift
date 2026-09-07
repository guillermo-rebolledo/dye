import Testing
import Foundation
import FilmEngine

/// The Geometry Pass runs after the Output Stage, so an identity Colour Cube and
/// the Working Space output leave the frame's own values on the way in.
private func flat(width: Int, height: Int, value: Float16) throws -> LinearImage {
    var rgba = [Float16](repeating: value, count: width * height * 4)
    for i in stride(from: 3, to: rgba.count, by: 4) { rgba[i] = 1 }
    return try LinearImage(width: width, height: height, rgba: rgba)
}

/// A horizontal ramp reads back a displacement directly: the value at a pixel says
/// which pixel the Pass sampled, to a fraction of one.
private func ramp(width: Int, height: Int) throws -> LinearImage {
    var rgba = [Float16](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            for c in 0..<3 { rgba[(y * width + x) * 4 + c] = Float16((Double(x) + 0.5) / Double(width)) }
            rgba[(y * width + x) * 4 + 3] = 1
        }
    }
    return try LinearImage(width: width, height: height, rgba: rgba)
}

@Test func theGeometryPassDoesNotRunUntilSomethingAsksItTo() async throws {
    let renderer = try Renderer()
    let image = try ramp(width: 128, height: 8)
    let result = try await renderer.render(image: .linear(image), profile: .identity, settings: .init(output: .workingSpace))
    #expect(result.rgba == image.rgba)
    for settings in [RenderSettings(output: .workingSpace, vignette: 1.5),
                     RenderSettings(output: .workingSpace, gateWeave: -0.1),
                     RenderSettings(output: .workingSpace, frameBorder: 2)] {
        await #expect(throws: FilmError.self) { _ = try await renderer.render(image: .linear(image), profile: .identity, settings: settings) }
    }
}

@Test func theVignetteFallsOffByTheLensLawAndKeepsItsShapeAtEveryResolution() async throws {
    let renderer = try Renderer()
    func rendered(width: Int, height: Int) async throws -> [Double] {
        let result = try await renderer.render(image: .linear(try flat(width: width, height: height, value: 0.5)),
                                               profile: .identity, settings: .init(output: .workingSpace, vignette: 1))
        return (0..<(width * height)).map { Double(result.rgba[$0 * 4]) }
    }
    let size = 256
    let values = try await rendered(width: size, height: size)
    func at(_ x: Int, _ y: Int) -> Double { values[y * size + x] }
    // cos⁴ of the angle off axis: two stops in the corners at full strength.
    #expect(abs(at(size / 2, size / 2) - 0.5) < 0.002)
    #expect(abs(at(0, 0) / 0.5 - 0.25) < 0.01)
    let corners = [at(0, 0), at(size - 1, 0), at(0, size - 1), at(size - 1, size - 1)]
    for corner in corners { #expect(abs(corner - corners[0]) < 0.001) }
    // Monotone from the centre outward along the diagonal, with no step in it.
    let diagonal = (0..<(size / 2)).map { at($0, $0) }
    #expect(zip(diagonal, diagonal.dropFirst()).allSatisfy { $0 < $1 })
    // A circle on the film, not an ellipse in pixels: the corner of a landscape
    // frame is as dark as the corner of a square one.
    let landscape = try await rendered(width: 512, height: 256)
    #expect(abs(landscape[0] - corners[0]) < 0.002)
    let larger = try await rendered(width: 1024, height: 1024)
    #expect(abs(larger[0] - corners[0]) < 0.002)
    #expect(abs(larger[512 * 1024 + 512] - at(size / 2, size / 2)) < 0.002)
}

@Test func theFrameBorderIsTheSameWidthOnTheFilmAtEveryResolution() async throws {
    let renderer = try Renderer()
    func width(_ size: Int) async throws -> Double {
        let result = try await renderer.render(image: .linear(try flat(width: size, height: size, value: 0.5)),
                                               profile: .identity, settings: .init(output: .workingSpace, frameBorder: 1))
        let row = (0..<size).map { Double(result.rgba[(size / 2 * size + $0) * 4]) }
        #expect(row[0] == 0)
        #expect(abs(row[size / 2] - 0.5) < 0.002)
        // The first fully exposed column, as a fraction of the frame.
        return Double(row.firstIndex { $0 >= 0.5 } ?? size) / Double(size)
    }
    let small = try await width(512)
    // 1.5 mm of rebate alongside a 36 mm frame at the full setting.
    #expect(abs(small - 1.5 / 36) < 0.005)
    #expect(abs(try await width(1024) - small) < 0.002)
}

@Test func gateWeaveDisplacesTheFrameByTheSameDistanceOnTheFilmAtEveryResolution() async throws {
    let renderer = try Renderer()
    /// The displacement in pixels, read off the ramp, as a fraction of the frame.
    func displacement(size: Int, seed: UInt32 = 0, weave: Double = 1) async throws -> Double {
        let image = try ramp(width: size, height: 8)
        let result = try await renderer.render(image: .linear(image), profile: .identity,
                                               settings: .init(output: .workingSpace, gateWeave: weave, seed: seed))
        let margin = size / 4
        let shifts = (margin..<(size - margin)).map {
            (Double(result.rgba[$0 * 4]) - Double(image.rgba[$0 * 4])) * Double(size)
        }
        return shifts.reduce(0, +) / Double(shifts.count) / Double(size)
    }
    let small = try await displacement(size: 512)
    #expect(abs(small) > 0.001)
    #expect(abs(try await displacement(size: 1024) - small) < 0.0005)
    // The seed fixes the displacement, so a still frame weaves once rather than
    // shimmering, and half the weave displaces half as far.
    #expect(try await displacement(size: 512) == small)
    #expect(try await displacement(size: 512, seed: 9) != small)
    #expect(abs(try await displacement(size: 512, weave: 0.5) - small / 2) < 0.001)
}
