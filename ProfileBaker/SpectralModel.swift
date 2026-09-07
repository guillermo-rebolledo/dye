import Foundation
import FilmEngine
import simd

/// Strict numerical tables shared by spectral authoring inputs. No extrapolated measurements.
struct SpectralTable {
    let rows: [[Double]]
    init(_ directory: URL, _ name: String, header: String) throws {
        let lines = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
            .components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard lines.first == header else { throw FilmError.invalid("\(name): expected \(header)") }
        let count = header.split(separator: ",").count
        var result: [[Double]] = []
        for line in lines.dropFirst() {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            let values = fields.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard values.count == count, fields.count == count,
                  values.allSatisfy({ $0.isFinite && $0 >= 0 }),
                  result.last.map({ values[0] > $0[0] }) ?? true else {
                throw FilmError.invalid("\(name): expected increasing samples and finite nonnegative values")
            }
            result.append(values)
        }
        guard !result.isEmpty else { throw FilmError.invalid("\(name): empty table") }
        rows = result
    }
}

struct SpectralModel {
    struct Parameters: Decodable {
        struct Development: Decodable {
            let offset: Double
            let contrast: Double
            let shadowLoss: Double
        }
        let dirCouplers: [[Double]]
        let dyePeakNM: [Double]
        let dyeWidthNM: [Double]
        let scanGamma: Double
        let development: [Development]
    }
    let parameters: Parameters
    let shaper: FilmProfile.LogExposureShaper
    let channels: [CharacteristicCurve]
    let basis: [SIMD3<Double>]
    let sensitivity: [SIMD3<Double>]
    let sensitivityNormalization: SIMD3<Double>
    let rgbToBasis: simd_double3x3
    let minimumDensity: [Double]
    let dyeContributions: [SIMD3<Double>]
    let scanner: [SIMD3<Double>]
    let clearScan: SIMD3<Double>
    let grayScanDensity: SIMD3<Double>
    let scannerToRGB: simd_double3x3
    let base: SIMD3<Double>
    let grayExcess: SIMD3<Double>

    init(curves: CurveSet) throws {
        guard let shaper = curves.metadata.colour.inputShaper else { throw FilmError.invalid("Missing spectral input shaper") }
        self.shaper = shaper
        parameters = try JSONDecoder().decode(Parameters.self, from: Data(contentsOf: curves.directory.appendingPathComponent("spectral.json")))
        let p = parameters
        guard p.dirCouplers.count == 3, p.dirCouplers.allSatisfy({ $0.count == 3 && $0.allSatisfy { $0.isFinite && (0...1).contains($0) } }),
              p.dyePeakNM.count == 3, p.dyePeakNM.allSatisfy({ $0.isFinite && (400...700).contains($0) }),
              p.dyeWidthNM.count == 3, p.dyeWidthNM.allSatisfy({ $0.isFinite && (5...150).contains($0) }),
              p.scanGamma.isFinite, (0.1...3).contains(p.scanGamma),
              Set(p.development.map(\.offset)) == Set(curves.metadata.colour.lutVariants.map(\.pushStops)),
              p.development.count == curves.metadata.colour.lutVariants.count,
              p.development.allSatisfy({ $0.offset.isFinite && $0.contrast.isFinite && (0.1...3).contains($0.contrast) && $0.shadowLoss.isFinite && (0...1).contains($0.shadowLoss) }),
              p.development.contains(where: { $0.offset == 0 && $0.contrast == 1 && $0.shadowLoss == 0 }) else {
            throw FilmError.invalid("Invalid spectral model parameters or Development Offsets")
        }
        let requiredProvenance = ["spectral.characteristicCurves", "spectral.sensitivity", "spectral.dyeDensity", "spectral.observer",
            "spectral.reconstruction", "spectral.dyeSeparation", "spectral.dirCouplers", "spectral.development", "spectral.scan",
            "spectral.dyePeakNM", "spectral.dyeWidthNM", "spectral.scanGamma"]
        guard requiredProvenance.allSatisfy({ curves.metadata.provenance[$0] != nil }) else {
            throw FilmError.invalid("Missing spectral per-parameter Provenance")
        }
        channels = try curves.characteristicCurves(for: "neutral.lut3d")
        guard channels.allSatisfy({ curve in
            zip(curve.points, curve.points.dropFirst()).allSatisfy { $0.density <= $1.density } &&
            curve.points.first!.logExposure >= shaper.minimumLogExposure && curve.points.last!.logExposure <= shaper.maximumLogExposure
        }) else { throw FilmError.invalid("Spectral Characteristic Curves must increase inside the input shaper") }
        let sensitivities = try SpectralTable(curves.directory, "sensitivity.csv", header: "wavelengthNM,red,green,blue").rows
        let dyes = try SpectralTable(curves.directory, "dye-density.csv", header: "wavelengthNM,minimum,midscale").rows
        let observer = try SpectralTable(curves.directory, "observer.csv", header: "wavelengthNM,x,y,z,illuminant").rows
        let grid = sensitivities.map { $0[0] }
        guard (31...81).contains(grid.count), grid.first == 400, grid.last == 700,
              dyes.map({ $0[0] }) == grid, observer.map({ $0[0] }) == grid,
              zip(grid, grid.dropFirst()).allSatisfy({ abs(($1 - $0) - 300 / Double(grid.count - 1)) < 0.00001 }),
              dyes.allSatisfy({ $0[2] > $0[1] }), observer.allSatisfy({ $0[4] > 0 }) else {
            throw FilmError.invalid("Spectral tables require a common uniform 31–81 band grid from 400 to 700 nm")
        }
        let mtf = try SpectralTable(curves.directory, "mtf.csv", header: "cyclesPerMM,red,green,blue").rows
        let rms = try SpectralTable(curves.directory, "rms-granularity.csv", header: "density,rmsGranularity").rows
        guard mtf.map({ $0[0] }) == curves.metadata.mtf.cyclesPerMM,
              mtf.map({ $0[2] }) == curves.metadata.mtf.response,
              rms.count == 1, rms[0][0] == 1, rms[0][1] == curves.metadata.grain.rmsGranularity else {
            throw FilmError.invalid("MTF or RMS CSV does not match Profile metadata")
        }
        base = SIMD3(channels[0].points[0].density, channels[1].points[0].density, channels[2].points[0].density)
        let grayH = pow(10, shaper.middleGrayLogExposure)
        grayExcess = SIMD3(channels[0].density(atLinearExposure: grayH), channels[1].density(atLinearExposure: grayH), channels[2].density(atLinearExposure: grayH)) - base
        guard grayExcess.x > 0 && grayExcess.y > 0 && grayExcess.z > 0 else { throw FilmError.invalid("Middle gray must be above base density") }
        func gaussian(_ nm: Double, _ peak: Double, _ width: Double) -> Double { exp(-0.5 * pow((nm - peak) / width, 2)) }
        var basis: [SIMD3<Double>] = []
        var scanner: [SIMD3<Double>] = []
        for row in observer {
            let nm = row[0]
            let lobes = SIMD3(gaussian(nm, 650, 45), gaussian(nm, 540, 35), gaussian(nm, 450, 30))
            basis.append(lobes / (lobes.x + lobes.y + lobes.z) * row[4])
            let weight = (nm == 400 || nm == 700) ? 0.5 : 1.0
            scanner.append(SIMD3(gaussian(nm, 650, 30), gaussian(nm, 550, 30), gaussian(nm, 450, 30)) * row[4] * weight)
        }
        // CIE integration gives this smooth spectral basis a colourimetric Rec.2020 input.
        // Normalize the truncated observer white to D65; saturated out-of-spectral-gamut
        // inputs are projected to nonnegative spectra after solving the basis coefficients.
        let rgbToXYZ = simd_double3x3(columns: (SIMD3(0.636958, 0.262700, 0), SIMD3(0.144617, 0.677998, 0.028073), SIMD3(0.168881, 0.059302, 1.060985)))
        var basisToXYZ = simd_double3x3(0)
        for i in grid.indices {
            let row = observer[i]
            let xyz = SIMD3(row[1], row[2], row[3]) * ((i == 0 || i == grid.count - 1) ? 0.5 : 1.0)
            for c in 0..<3 { basisToXYZ[c] += xyz * basis[i][c] }
        }
        let white = basisToXYZ * SIMD3<Double>(repeating: 1)
        guard (0..<3).allSatisfy({ white[$0] > 0 }) else { throw FilmError.invalid("Observer has no white response") }
        let whiteScale = (rgbToXYZ * SIMD3<Double>(repeating: 1)) / white
        for c in 0..<3 { basisToXYZ[c] *= whiteScale }
        guard abs(simd_determinant(basisToXYZ)) > 1e-8 else { throw FilmError.invalid("Singular observer basis") }
        self.rgbToBasis = basisToXYZ.inverse * rgbToXYZ
        self.basis = basis
        self.scanner = scanner
        sensitivity = sensitivities.enumerated().map { i, row in
            SIMD3(row[1], row[2], row[3]) * ((i == 0 || i == grid.count - 1) ? 0.5 : 1.0)
        }
        sensitivityNormalization = zip(sensitivity, basis).reduce(SIMD3<Double>(repeating: 0)) { $0 + $1.0 * ($1.1.x + $1.1.y + $1.1.z) }
        guard sensitivityNormalization.x > 0 && sensitivityNormalization.y > 0 && sensitivityNormalization.z > 0 else { throw FilmError.invalid("Empty film sensitivity channel") }
        minimumDensity = dyes.map { $0[1] }
        dyeContributions = dyes.map { row in
            let lobes = SIMD3(gaussian(row[0], p.dyePeakNM[0], p.dyeWidthNM[0]), gaussian(row[0], p.dyePeakNM[1], p.dyeWidthNM[1]), gaussian(row[0], p.dyePeakNM[2], p.dyeWidthNM[2]))
            return lobes / (lobes.x + lobes.y + lobes.z) * (row[2] - row[1])
        }
        func scan(_ column: Int) -> SIMD3<Double> {
            zip(dyes, scanner).reduce(SIMD3<Double>(repeating: 0)) { $0 + $1.1 * pow(10, -$1.0[column]) }
        }
        clearScan = scan(1)
        let grayTransmission = scan(2) / clearScan
        grayScanDensity = SIMD3(-log10(grayTransmission.x), -log10(grayTransmission.y), -log10(grayTransmission.z))
        // Calibrate the scanner's broad channels back to the Working Space primaries.
        var basisToScanner = simd_double3x3(0)
        let scannerWhite = scanner.reduce(SIMD3<Double>(repeating: 0), +)
        for i in grid.indices {
            for c in 0..<3 { basisToScanner[c] += scanner[i] * (basis[i][c] / observer[i][4]) / scannerWhite }
        }
        let rgbToScanner = basisToScanner * self.rgbToBasis
        guard abs(simd_determinant(rgbToScanner)) > 1e-8 else { throw FilmError.invalid("Singular scanner calibration") }
        scannerToRGB = rgbToScanner.inverse
    }

    func exposure(at coordinate: Double) -> Double {
        pow(10, shaper.minimumLogExposure + coordinate * (shaper.maximumLogExposure - shaper.minimumLogExposure))
    }

    func density(_ rgbExposure: SIMD3<Double>, offset: Double) -> SIMD3<Double> {
        let coefficients = rgbToBasis * rgbExposure
        var exposure = SIMD3<Double>(repeating: 0)
        for i in basis.indices { exposure += sensitivity[i] * max(0, simd_dot(basis[i], coefficients)) }
        exposure /= sensitivityNormalization
        let development = parameters.development.first { $0.offset == offset }!
        func developed(_ channel: Int, _ logH: Double) -> Double {
            let distance = logH - shaper.middleGrayLogExposure
            let adjusted = shaper.middleGrayLogExposure + development.contrast * distance - development.shadowLoss * max(-distance, 0)
            return channels[channel].density(atLinearExposure: pow(10, adjusted))
        }
        let logs = SIMD3(log10(max(exposure.x, 1e-12)), log10(max(exposure.y, 1e-12)), log10(max(exposure.z, 1e-12)))
        let initial = SIMD3(developed(0, logs.x), developed(1, logs.y), developed(2, logs.z))
        var result = initial
        for c in 0..<3 {
            var inhibition = 0.0
            for other in 0..<3 {
                // Published neutral curves already include DIR. Subtract only the
                // departure from neutral development to avoid counting it twice.
                inhibition += parameters.dirCouplers[c][other] * (initial[other] - developed(other, logs[c]))
            }
            result[c] = developed(c, logs[c] - inhibition)
        }
        return result
    }

    func scan(_ density: SIMD3<Double>) -> SIMD3<Double> {
        let amounts = simd_max(density - base, SIMD3<Double>(repeating: 0)) / grayExcess
        var transmission = SIMD3<Double>(repeating: 0)
        for i in scanner.indices {
            let spectralDensity = minimumDensity[i] + simd_dot(dyeContributions[i], amounts)
            transmission += scanner[i] * pow(10, -spectralDensity)
        }
        transmission /= clearScan
        var positive = SIMD3<Double>(repeating: 0)
        for c in 0..<3 {
            let d = -log10(max(transmission[c], 1e-12))
            let signal = max(0, pow(10, d / parameters.scanGamma) - 1)
            let gray = pow(10, grayScanDensity[c] / parameters.scanGamma) - 1
            let linear = (0.18 / 0.82) * signal / gray
            positive[c] = linear / (1 + linear)
        }
        return simd_clamp(scannerToRGB * positive, SIMD3<Double>(repeating: 0), SIMD3<Double>(repeating: 1))
    }

    func cube(offset: Double, densityOnly: Bool = false) throws -> ColourCube {
        var rgba: [Float16] = []
        rgba.reserveCapacity(33 * 33 * 33 * 4)
        for b in 0..<33 { for g in 0..<33 { for r in 0..<33 {
            let d = density(SIMD3(exposure(at: Double(r) / 32), exposure(at: Double(g) / 32), exposure(at: Double(b) / 32)), offset: offset)
            let value = densityOnly ? d : scan(d)
            rgba += [Float16(value.x), Float16(value.y), Float16(value.z), 1]
        } } }
        return try ColourCube(size: 33, rgba: rgba)
    }
}
