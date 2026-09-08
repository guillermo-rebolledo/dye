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
        /// Negative stocks only: the artistic Gaussian lobes the aggregate measured
        /// absorption is separated into, because Kodak publishes no isolated dyes.
        let dyePeakNM: [Double]?
        let dyeWidthNM: [Double]?
        /// Negative stocks only: the scanner's transfer, which reversal has no use for.
        let scanGamma: Double?
        let development: [Development]
    }
    /// Reversal skips the inversion and the print, because the film already is the
    /// final image, and is viewed by transmission instead of being scanned.
    let isReversal: Bool
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
    /// The viewing light and observer a transparency is read by, and the transform
    /// from what they measure to the Working Space. Reversal only.
    let observerXYZ: [SIMD3<Double>]
    let xyzToRGB: simd_double3x3
    let viewingScale: SIMD3<Double>
    /// The Stock's minimum density: the first plotted point for a negative, the
    /// last for a reversal Stock, whose curve falls as exposure rises.
    let base: SIMD3<Double>
    let grayExcess: SIMD3<Double>

    init(curves: CurveSet) throws {
        guard let shaper = curves.metadata.colour.inputShaper else { throw FilmError.invalid("Missing spectral input shaper") }
        self.shaper = shaper
        parameters = try JSONDecoder().decode(Parameters.self, from: Data(contentsOf: curves.directory.appendingPathComponent("spectral.json")))
        let p = parameters
        let reversal = curves.metadata.process == .e6
        isReversal = reversal
        guard p.dirCouplers.count == 3, p.dirCouplers.allSatisfy({ $0.count == 3 && $0.allSatisfy { $0.isFinite && (0...1).contains($0) } }),
              reversal || (p.dyePeakNM?.count == 3 && p.dyePeakNM!.allSatisfy { $0.isFinite && (400...700).contains($0) }),
              reversal || (p.dyeWidthNM?.count == 3 && p.dyeWidthNM!.allSatisfy { $0.isFinite && (5...150).contains($0) }),
              reversal || (p.scanGamma.map { $0.isFinite && (0.1...3).contains($0) } ?? false),
              !reversal || (p.dyePeakNM == nil && p.dyeWidthNM == nil && p.scanGamma == nil),
              Set(p.development.map(\.offset)) == Set(curves.metadata.colour.lutVariants.map(\.pushStops)),
              p.development.count == curves.metadata.colour.lutVariants.count,
              p.development.allSatisfy({ $0.offset.isFinite && $0.contrast.isFinite && (0.1...3).contains($0.contrast) && $0.shadowLoss.isFinite && (0...1).contains($0.shadowLoss) }),
              p.development.contains(where: { $0.offset == 0 && $0.contrast == 1 && $0.shadowLoss == 0 }) else {
            throw FilmError.invalid("Invalid spectral model parameters or Development Offsets")
        }
        let requiredProvenance = ["spectral.characteristicCurves", "spectral.sensitivity", "spectral.dyeDensity", "spectral.observer",
            "spectral.reconstruction", "spectral.dirCouplers", "spectral.development"]
            + (reversal ? ["spectral.viewing"]
                        : ["spectral.dyeSeparation", "spectral.scan", "spectral.dyePeakNM", "spectral.dyeWidthNM", "spectral.scanGamma"])
        guard requiredProvenance.allSatisfy({ curves.metadata.provenance[$0] != nil }) else {
            throw FilmError.invalid("Missing spectral per-parameter Provenance")
        }
        channels = try curves.characteristicCurves(for: "neutral.lut3d")
        // A negative gains density with exposure and a reversal Stock loses it;
        // either way the curve has to be monotone, or the Film Response is not a
        // response to anything.
        guard channels.allSatisfy({ curve in
            zip(curve.points, curve.points.dropFirst()).allSatisfy { reversal ? $0.density >= $1.density : $0.density <= $1.density } &&
            curve.points.first!.logExposure >= shaper.minimumLogExposure && curve.points.last!.logExposure <= shaper.maximumLogExposure
        }) else { throw FilmError.invalid("Spectral Characteristic Curves must be monotone inside the input shaper") }
        let sensitivities = try SpectralTable(curves.directory, "sensitivity.csv", header: "wavelengthNM,red,green,blue").rows
        // A negative publishes the aggregate minimum and midscale neutral densities
        // and the model separates them; a reversal datasheet publishes the isolated
        // dyes themselves, peak-normalised, and there is nothing to separate.
        let dyes = try SpectralTable(curves.directory, "dye-density.csv",
                                     header: reversal ? "wavelengthNM,cyan,magenta,yellow" : "wavelengthNM,minimum,midscale").rows
        let observer = try SpectralTable(curves.directory, "observer.csv", header: "wavelengthNM,x,y,z,illuminant").rows
        let grid = sensitivities.map { $0[0] }
        guard (31...81).contains(grid.count), grid.first == 400, grid.last == 700,
              dyes.map({ $0[0] }) == grid, observer.map({ $0[0] }) == grid,
              zip(grid, grid.dropFirst()).allSatisfy({ abs(($1 - $0) - 300 / Double(grid.count - 1)) < 0.00001 }),
              reversal || dyes.allSatisfy({ $0[2] > $0[1] }),
              !reversal || (dyes.allSatisfy { $0.dropFirst().allSatisfy { (0...1).contains($0) } }
                              && (1...3).allSatisfy { column in dyes.contains { abs($0[column] - 1) < 1e-9 } }),
              observer.allSatisfy({ $0[4] > 0 }) else {
            throw FilmError.invalid("Spectral tables require a common uniform 31–81 band grid from 400 to 700 nm")
        }
        let mtf = try SpectralTable(curves.directory, "mtf.csv", header: "cyclesPerMM,red,green,blue").rows
        let rms = try SpectralTable(curves.directory, "rms-granularity.csv", header: "density,rmsGranularity").rows
        guard mtf.map({ $0[0] }) == curves.metadata.mtf.cyclesPerMM,
              mtf.map({ $0[2] }) == curves.metadata.mtf.response,
              rms.count == 1, rms[0][0] == 1, rms[0][1] == curves.metadata.grain.rmsGranularity else {
            throw FilmError.invalid("MTF or RMS CSV does not match Profile metadata")
        }
        func endpointDensity(_ curve: CharacteristicCurve) -> Double {
            reversal ? curve.points[curve.points.count - 1].density : curve.points[0].density
        }
        base = SIMD3(endpointDensity(channels[0]), endpointDensity(channels[1]), endpointDensity(channels[2]))
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
        if reversal {
            // No Orange Mask: a transparency's base is the film support and the
            // residual fog, which the datasheet reports only as the three integral
            // minimum densities. A spectrally flat base at their mean reproduces
            // every one of them through any channel, and claims nothing else.
            let flat = (base.x + base.y + base.z) / 3
            minimumDensity = grid.map { _ in flat }
            // The published curves are the isolated dyes themselves, so a layer's
            // amount scales its own measured absorption. Index 0 is the red-sensitive
            // layer and the cyan dye it forms, and so on.
            //
            // The chart is drawn peak-normalised, so it says the dyes' shapes and
            // not their amplitudes. Rather than author three numbers, solve for the
            // amplitudes that reproduce the Curve Set's own measured density above
            // base at the reference neutral, read at each dye's own peak wavelength
            // where that dye dominates: three equations from three measurements.
            // Anything left over is the neighbouring dyes' overlap there, which is
            // the approximation, not a free parameter.
            let peakBand = (1...3).map { column in dyes.indices.max { dyes[$0][column] < dyes[$1][column] }! }
            var shapes = simd_double3x3(0)
            for dye in 0..<3 {
                shapes[dye] = SIMD3(dyes[peakBand[0]][dye + 1], dyes[peakBand[1]][dye + 1], dyes[peakBand[2]][dye + 1])
            }
            guard abs(simd_determinant(shapes)) > 1e-6 else { throw FilmError.invalid("The dye set does not separate at its own peaks") }
            let peaks = shapes.inverse * grayExcess
            guard peaks.min() > 0 else { throw FilmError.invalid("The dye set cannot reach the reference neutral's density") }
            dyeContributions = dyes.map { SIMD3($0[1] * peaks[0], $0[2] * peaks[1], $0[3] * peaks[2]) }
        } else {
            minimumDensity = dyes.map { $0[1] }
            dyeContributions = dyes.map { row in
                let lobes = SIMD3(gaussian(row[0], p.dyePeakNM![0], p.dyeWidthNM![0]),
                                  gaussian(row[0], p.dyePeakNM![1], p.dyeWidthNM![1]),
                                  gaussian(row[0], p.dyePeakNM![2], p.dyeWidthNM![2]))
                return lobes / (lobes.x + lobes.y + lobes.z) * (row[2] - row[1])
            }
        }
        // A transparency is looked at rather than scanned, so the viewing light and
        // the CIE observer replace the scanner's three broad channels outright.
        observerXYZ = grid.indices.map { i in
            SIMD3(observer[i][1], observer[i][2], observer[i][3]) * observer[i][4] * ((i == 0 || i == grid.count - 1) ? 0.5 : 1)
        }
        xyzToRGB = rgbToXYZ.inverse
        if reversal {
            // The reference neutral lands on Working Space mid-grey in every channel:
            // a standard viewer is a defined white, and the Curve Set's own neutral
            // exposure is what defines neutral on this Stock. What the projection
            // then carries is the dyes' saturation and the curve's contrast, not a
            // white balance the datasheet never published.
            var reference = SIMD3<Double>(repeating: 0)
            for i in grid.indices {
                reference += observerXYZ[i] * pow(10, -(minimumDensity[i] + simd_reduce_add(dyeContributions[i])))
            }
            let rgb = xyzToRGB * reference
            guard rgb.x > 0 && rgb.y > 0 && rgb.z > 0 else { throw FilmError.invalid("The reference neutral is not visible through the dye set") }
            viewingScale = SIMD3(repeating: 0.18) / rgb
        } else {
            viewingScale = SIMD3(repeating: 1)
        }
        func scan(_ column: Int) -> SIMD3<Double> {
            zip(dyes, scanner).reduce(SIMD3<Double>(repeating: 0)) { $0 + $1.1 * pow(10, -$1.0[column]) }
        }
        clearScan = reversal ? SIMD3(repeating: 1) : scan(1)
        let grayTransmission = reversal ? SIMD3<Double>(repeating: 1) : scan(2) / clearScan
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

    /// What comes out of the film: a negative's scan, or the transparency itself.
    func output(_ density: SIMD3<Double>) -> SIMD3<Double> {
        isReversal ? project(density) : scan(density)
    }

    /// A transparency on a standard viewer. No inversion and no auto-balance: the
    /// dyes are read by transmission and that is already the picture. Nothing
    /// rolls the highlights off either, which is where reversal's roughly five
    /// stops of Latitude come from — above the reference neutral the film runs out
    /// of density to lose, and everything brighter clips to clear film.
    func project(_ density: SIMD3<Double>) -> SIMD3<Double> {
        let amounts = simd_max(density - base, SIMD3<Double>(repeating: 0)) / grayExcess
        var xyz = SIMD3<Double>(repeating: 0)
        for i in observerXYZ.indices {
            xyz += observerXYZ[i] * pow(10, -(minimumDensity[i] + simd_dot(dyeContributions[i], amounts)))
        }
        // Not clamped above: clear film is brighter than Working Space mid-grey and
        // the Working Space carries that, exactly as it carries any other highlight.
        // Clipping to a delivery range is the file writer's job, and a clamp here
        // would put a corner in the Colour Cube that its own interpolation cannot
        // follow. Below zero is out of gamut rather than headroom, so it goes.
        return simd_max(xyzToRGB * xyz * viewingScale, SIMD3(repeating: 0))
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
            let signal = max(0, pow(10, d / parameters.scanGamma!) - 1)
            let gray = pow(10, grayScanDensity[c] / parameters.scanGamma!) - 1
            let linear = (0.18 / 0.82) * signal / gray
            positive[c] = linear / (1 + linear)
        }
        return simd_clamp(scannerToRGB * positive, SIMD3<Double>(repeating: 0), SIMD3<Double>(repeating: 1))
    }

    /// A Stock whose Characteristic Curve bends more sharply than the cube's node
    /// spacing can follow needs more nodes, not a wider tolerance; `size` is the
    /// Curve Set's own `colour.lutSize`.
    func cube(offset: Double, size: Int, densityOnly: Bool = false) throws -> ColourCube {
        let last = Double(size - 1)
        var rgba = [Float16](repeating: 1, count: size * size * size * 4)
        // A 65³ cube is a quarter of a million spectral integrations and every
        // texel is independent of every other. The Baker is offline, but a bake
        // and its Step Wedge both sit in CI on every push.
        rgba.withUnsafeMutableBufferPointer { buffer in
            nonisolated(unsafe) let texels = buffer
            DispatchQueue.concurrentPerform(iterations: size) { b in
                for g in 0..<size {
                    for r in 0..<size {
                        let d = density(SIMD3(exposure(at: Double(r) / last), exposure(at: Double(g) / last),
                                              exposure(at: Double(b) / last)), offset: offset)
                        let value = densityOnly ? d : output(d)
                        let texel = ((b * size + g) * size + r) * 4
                        texels[texel] = Float16(value.x)
                        texels[texel + 1] = Float16(value.y)
                        texels[texel + 2] = Float16(value.z)
                    }
                }
            }
        }
        return try ColourCube(size: size, rgba: rgba)
    }
}
