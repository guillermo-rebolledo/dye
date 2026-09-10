import Foundation
import Testing
import FilmEngine

private func densityObservation(squared: Bool) throws -> Profile {
    var metadata = Profile.identity.metadata
    metadata.id = squared ? "quadratic-observer" : "linear-observer"
    metadata.process = .c41
    metadata.colour.outputStage = .scan
    metadata.colour.inputShaper = .init(minimumLogExposure: -3, maximumLogExposure: 1, middleGrayLogExposure: 0)
    metadata.colour.cubeOutput = .density
    metadata.colour.lutSize = 33
    metadata.colour.lutVariants = [.init(pushStops: 0, lut: "density.lut3d")]
    metadata.colour.densityOutput = .init(minimum: [0, 0, 0], maximum: [3, 3, 3], lutSize: 65,
                                        lutVariants: [.init(pushStops: 0, lut: "output.lut3d")], printVariants: nil)
    metadata.provenance["colour.inputShaper"] = .artistic
    metadata.provenance["colour.cubeOutput"] = .artistic
    metadata.grain = .init(model: .procedural, rmsGranularity: 0.05, grainRadiusMicrons: 1,
                           densityResponse: Array(repeating: 1, count: 32), channelCorrelation: 0,
                           channelRadiusScale: [1, 1, 1])
    func cube(size: Int, transform: (Double) -> Double) throws -> Data {
        var pixels: [Float16] = []
        for b in 0..<size { for g in 0..<size { for r in 0..<size {
            pixels += [r, g, b].map { Float16(transform(Double($0) / Double(size - 1))) } + [1]
        } } }
        return try ColourCube(size: size, rgba: pixels).payload
    }
    return try Profile(metadata: metadata, payloads: [
        "density.lut3d": cube(size: 33) { $0 * 2 },
        "output.lut3d": cube(size: 65) { squared ? pow($0 * 3, 2) / 10 : $0 * 3 }
    ])
}

@Test func colourDensityGrainTravelsThroughTheObservationTransform() async throws {
    let renderer = try Renderer()
    let linear = try densityObservation(squared: false)
    let quadratic = try densityObservation(squared: true)
    let pixels = (0..<(128 * 128)).flatMap { _ in [Float16(0.18), 0.18, 0.18, 1] }
    let image = try LinearImage(width: 128, height: 128, rgba: pixels)
    let settings = RenderSettings(output: .workingSpace, halationIntensity: 0, bloomIntensity: 0)
    let density = try await renderer.render(image: .linear(image), profile: linear, settings: settings)
    let observed = try await renderer.render(image: .linear(image), profile: quadratic, settings: settings)
    for i in stride(from: 0, to: pixels.count, by: 4) {
        for c in 0..<3 {
            let expected = pow(Double(density.rgba[i + c]), 2) / 10
            #expect(abs(Double(observed.rgba[i + c]) - expected) < 0.001)
        }
    }
    // This must not succeed merely because grain disappeared again.
    let red = stride(from: 0, to: pixels.count, by: 4).map { Double(density.rgba[$0]) }
    #expect(red.max()! - red.min()! > 0.01)
}

@Test func densityOutputCodecRejectsMismatchedDomainsAndVariants() throws {
    let profile = try densityObservation(squared: false)
    let decoded = try ProfileContainer.decode(ProfileContainer.encode(profile))
    #expect(decoded.metadata == profile.metadata)
    var metadata = profile.metadata
    metadata.colour.densityOutput!.maximum[0] = metadata.colour.densityOutput!.minimum[0]
    #expect(throws: FilmError.self) { try metadata.validate() }
    metadata = profile.metadata
    metadata.colour.densityOutput!.lutVariants[0].pushStops = 2
    #expect(throws: FilmError.self) { try metadata.validate() }
}
