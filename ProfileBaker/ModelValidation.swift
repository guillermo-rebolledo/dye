import Foundation
import FilmEngine
import simd

/// Deterministic coverage of the full cube, including saturated off-grid colours.
/// This bounds approximation error; it is not a film-photograph comparison.
func spectralValidationCoordinates() -> [SIMD3<Double>] {
    func halton(_ index: Int, base: Int) -> Double {
        var index = index, scale = 1.0, result = 0.0
        while index > 0 {
            scale /= Double(base)
            result += scale * Double(index % base)
            index /= base
        }
        return result
    }
    var points = (0...128).map { SIMD3<Double>(repeating: Double($0) / 128) }
    points += (1...512).map { SIMD3(halton($0, base: 2), halton($0, base: 3), halton($0, base: 5)) }
    for b in [0.0, 1] { for g in [0.0, 1] { for r in [0.0, 1] { points.append(SIMD3(r, g, b)) } } }
    return points
}

struct ModelValidationResult: Codable {
    let stage: String
    let developmentOffset: Double
    let samples: Int
    let maximumError: Double
    let rmsError: Double
}

func validateNumericalModel(curves: CurveSet, profile: Profile) throws -> [ModelValidationResult] {
    guard !curves.metadata.process.isMonochrome, curves.metadata.colour.inputShaper != nil,
          profile.metadata == (try curves.bakedMetadata), let output = profile.metadata.colour.densityOutput else {
        throw FilmError.invalid("Model validation requires a current baked spectral colour Profile")
    }
    let model = try SpectralModel(curves: curves)
    let bytes = try ProfileContainer.encode(profile)
    // The public codec validates every payload; use its encoded entries for the
    // offline comparison without introducing an independent profile loader.
    let count = Int(bytes[12]) | Int(bytes[13]) << 8 | Int(bytes[14]) << 16 | Int(bytes[15]) << 24
    struct Entry: Decodable { let name: String; let offset: Int; let length: Int }
    struct Header: Decodable { let payloads: [Entry] }
    let header = try JSONDecoder().decode(Header.self, from: bytes.subdata(in: 16..<(16 + count)))
    func cube(_ name: String, size: Int) throws -> ColourCube {
        guard let entry = header.payloads.first(where: { $0.name == name }) else { throw FilmError.invalid("Missing cube") }
        let start = 16 + count + entry.offset
        return try ColourCube(size: size, payload: bytes.subdata(in: start..<(start + entry.length)))
    }
    let minimum = SIMD3(output.minimum[0], output.minimum[1], output.minimum[2])
    let span = SIMD3(output.maximum[0], output.maximum[1], output.maximum[2]) - minimum
    let probes = spectralValidationCoordinates()
    var results: [ModelValidationResult] = []
    for printStage in [false, true] {
        guard !printStage || profile.metadata.colour.printVariants != nil else { continue }
        let variants = printStage ? profile.metadata.colour.printVariants! : profile.metadata.colour.lutVariants
        let outputs = printStage ? output.printVariants! : output.lutVariants
        for variant in variants {
            let response = try cube(variant.lut, size: profile.metadata.colour.lutSize)
            let observation = try cube(outputs.first { $0.pushStops == variant.pushStops }!.lut, size: output.lutSize)
            var paper: PrintModel?
            if printStage {
                paper = try PrintModel(directory: curves.printPaperDirectory, basis: model.basis)
                try paper!.balance(against: model, offset: variant.pushStops)
            }
            var maximum = 0.0, squared = 0.0
            for p in probes {
                let physical = SIMD3(model.exposure(at: p.x), model.exposure(at: p.y), model.exposure(at: p.z))
                let expectedDensity = model.density(physical, offset: variant.pushStops)
                let expected = paper.map { $0.print(expectedDensity, negative: model) } ?? model.output(expectedDensity)
                let density = response.sample(p)
                // The film and grain textures use half precision at runtime.
                let half = SIMD3(Double(Float16(density.x)), Double(Float16(density.y)), Double(Float16(density.z)))
                let observed = observation.sample((half - minimum) / span)
                for c in 0..<3 {
                    let error = abs(Double(Float16(observed[c])) - expected[c])
                    guard error.isFinite else { throw FilmError.invalid("Nonfinite output interpolation") }
                    maximum = max(maximum, error); squared += error * error
                }
            }
            let count = probes.count * 3
            results.append(.init(stage: printStage ? "print-output" : (model.isReversal ? "reversal-output" : "scan-output"),
                                 developmentOffset: variant.pushStops, samples: count,
                                 maximumError: maximum, rmsError: sqrt(squared / Double(count))))
        }
    }
    return results
}
