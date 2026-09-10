import Foundation
import FilmEngine

func bake(_ curves: CurveSet) throws -> Profile {
    var payloads: [String: Data] = [:]
    if curves.metadata.colour.inputShaper != nil, curves.metadata.process.isMonochrome {
        // The Spectral Weight and the Contrast Filters are integrated here rather than
        // authored, so a B&W Profile cannot ship a guessed channel mix.
        let model = try MonochromeSpectralModel(curves: curves)
        return try Profile(metadata: try curves.bakedMetadata, payloads: [model.densityCurveName: model.densityCurve])
    }
    if curves.metadata.colour.inputShaper != nil {
        let model = try SpectralModel(curves: curves)
        let size = curves.metadata.colour.lutSize
        let metadata = try curves.bakedMetadata
        let output = metadata.colour.densityOutput!
        let scanned = try model.outputCube(domain: output).payload
        for variant in curves.metadata.colour.lutVariants {
            payloads[variant.lut] = try model.cube(offset: variant.pushStops, size: size, densityOnly: true).payload
        }
        payloads["output.scan.lut3d"] = scanned
        // The enlarger is filtered and its exposure set per Development Offset, the
        // way a lab prints each roll to its own neutral, and the way the runtime
        // scan auto-balances against each variant's own mid-grey density.
        for variant in output.printVariants ?? [] {
            var paper = try PrintModel(directory: curves.printPaperDirectory, basis: model.basis)
            try paper.balance(against: model, offset: variant.pushStops)
            payloads[variant.lut] = try model.outputCube(domain: output, paper: paper).payload
        }
        return try Profile(metadata: metadata, payloads: payloads)
    }
    if let monochrome = curves.metadata.monochrome {
        let curve = try curves.characteristicCurves(for: monochrome.densityCurve)[0]
        var bytes = Data()
        for i in 0..<1024 {
            let bits = Float16(curve.density(atLinearExposure: Double(i) / 1023)).bitPattern
            bytes.append(UInt8(truncatingIfNeeded: bits))
            bytes.append(UInt8(truncatingIfNeeded: bits >> 8))
        }
        payloads[monochrome.densityCurve] = bytes
    } else {
        let size = curves.metadata.colour.lutSize
        for variant in curves.metadata.colour.lutVariants {
            let channels = try curves.characteristicCurves(for: variant.lut)
            var rgba: [Float16] = []
            rgba.reserveCapacity(size * size * size * 4)
            for b in 0..<size { for g in 0..<size { for r in 0..<size {
                rgba += [Float16(channels[0].density(atLinearExposure: Double(r) / Double(size - 1))),
                         Float16(channels[1].density(atLinearExposure: Double(g) / Double(size - 1))),
                         Float16(channels[2].density(atLinearExposure: Double(b) / Double(size - 1))), 1]
            } } }
            payloads[variant.lut] = try ColourCube(size: size, rgba: rgba).payload
        }
    }
    return try Profile(metadata: curves.bakedMetadata, payloads: payloads)
}
