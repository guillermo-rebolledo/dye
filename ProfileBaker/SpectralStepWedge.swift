import Foundation
import FilmEngine

/// The density gate is before scan inversion: a positive scan value is not optical
/// density. A diagnostic Colour Cube traverses the same model and public renderer.
/// Separately compare the supplied scan cubes against the direct spectral result.
func spectralStepWedge(curves: CurveSet, profile: Profile) async throws -> [StepWedgeRow] {
    let model = try SpectralModel(curves: curves)
    let renderer = try Renderer()
    let diagnostic = Profile(colourCube: try model.cube(offset: 0, densityOnly: true))
    var rows: [StepWedgeRow] = []
    for (channel, curve) in model.channels.enumerated() {
        var samples = curve.points.map { ($0.logExposure, $0.density) }
        samples += zip(curve.points, curve.points.dropFirst()).map { (($0.logExposure + $1.logExposure) / 2, ($0.density + $1.density) / 2) }
        samples.sort { $0.0 < $1.0 }
        let pixels = samples.flatMap { logH, _ -> [Float16] in
            let coordinate = Float16((logH - model.shaper.minimumLogExposure) / (model.shaper.maximumLogExposure - model.shaper.minimumLogExposure))
            return [coordinate, coordinate, coordinate, 1]
        }
        let rendered = try await renderer.render(image: .linear(try LinearImage(width: samples.count, height: 1, rgba: pixels)),
            profile: diagnostic, settings: .init(output: .workingSpace))
        for (index, sample) in samples.enumerated() {
            rows.append(StepWedgeRow(stage: .measuredDensity, developmentOffset: 0, channel: channel, logExposure: sample.0,
                reference: sample.1, rendered: Double(rendered.rgba[index * 4 + channel])))
        }
    }
    // Off-grid neutral and chromatic probes check the shipped payload, interpolation,
    // float16 quantisation and each Development Offset. This is numerical bake QA,
    // not independent evidence of the tuned colour or push/pull model's accuracy.
    var coordinates = (0...64).map { SIMD3<Double>(repeating: Double($0) / 64) }
    coordinates += [SIMD3(0.31, 0.53, 0.72), SIMD3(0.8, 0.2, 0.4), SIMD3(0.45, 0.7, 0.2), SIMD3(0.72, 0.59, 0.46)]
    for variant in curves.metadata.colour.lutVariants {
        // Coordinates are already shaped, so undo the runtime shaper by feeding
        // scene-linear light and cancel the push rating with an equal exposure.
        let scene = coordinates.flatMap { c in
            (0..<3).map { Float16(model.exposure(at: c[$0]) / pow(10, model.shaper.middleGrayLogExposure) * 0.18) } + [1]
        }
        let rendered = try await renderer.render(image: .linear(try LinearImage(width: coordinates.count, height: 1, rgba: scene)), profile: profile,
            settings: .init(output: .workingSpace, exposureStops: variant.pushStops, developmentOffset: variant.pushStops))
        for (index, coordinate) in coordinates.enumerated() {
            let h = SIMD3(model.exposure(at: coordinate.x), model.exposure(at: coordinate.y), model.exposure(at: coordinate.z))
            let reference = model.scan(model.density(h, offset: variant.pushStops))
            for channel in 0..<3 {
                rows.append(StepWedgeRow(stage: index < 65 ? .scanOutput : .chromaticOutput, developmentOffset: variant.pushStops, channel: channel,
                    logExposure: log10(h[channel]), reference: reference[channel], rendered: Double(rendered.rgba[index * 4 + channel])))
            }
        }
    }
    return rows
}
