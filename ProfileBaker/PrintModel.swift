import Foundation
import FilmEngine
import simd

/// The Print Output Stage: an optical enlargement onto RA-4 paper, in place of the
/// scanner's inversion and auto-balance.
///
/// The chain is the darkroom's. An enlarger lamp shines through the negative; a
/// dichroic filter pack colours that light; the paper's three layers each integrate
/// what reaches them against their own spectral sensitivity; each layer's published
/// characteristic curve turns that exposure into density; and the dyes those
/// densities represent are read by reflection under the same Viewing Light the
/// reversal branch reads a Transparency by.
///
/// Two things are solved rather than authored, and they are the two a printer sets:
/// the **filter pack**, so the Curve Set's own reference neutral lands on the
/// paper's aim, and the **exposure**, which is the pack's neutral-density part.
struct PrintModel {
    /// Kodak's Laboratory Aim Density for a reflection print: the neutral patch a
    /// correctly filtered, correctly exposed print puts at 1.0.
    static let aimDensity = 1.0

    /// The enlarger's lamp, in kelvin. A tungsten-halogen head, which is what the
    /// paper's own sensitometry is exposed under.
    static let lampKelvin = 3200.0

    /// Per band, the paper's spectral sensitivity for its red-, green- and
    /// blue-sensitive layers, already carrying its band's quadrature weight.
    let sensitivity: [SIMD3<Double>]
    /// Per band, the paper's isolated cyan, magenta and yellow dyes, peak-normalised
    /// as Kodak draws them. They are both what the print is made of and the shapes
    /// the dichroic filter pack subtracts with.
    let dyes: [SIMD3<Double>]
    /// The paper's base, modelled spectrally flat at the mean of its three measured
    /// minimum densities, exactly as the reversal branch models a transparency's.
    let base: Double
    /// Each layer's minimum density, which is what its characteristic curve's own
    /// density has to be read above to become an amount of dye.
    let minimumDensity: SIMD3<Double>
    /// The paper's three published characteristic curves, addressed in log10
    /// lux-seconds at the paper.
    let curves: [CharacteristicCurve]
    /// Per band, the enlarger lamp's spectral radiance, quadrature weighted.
    let lamp: [Double]
    /// Where each layer's own curve reaches the aim density.
    let aim: SIMD3<Double>

    /// The dichroic filter pack, in density at each filter's own peak, ordered
    /// cyan/magenta/yellow — the filters that hold back the paper's red-, green- and
    /// blue-sensitive layers. Its three components sum to zero: a pack's common part
    /// is neutral density, which is an exposure time rather than a colour, and that
    /// part lives in `exposure` instead.
    private(set) var filtration = SIMD3<Double>(repeating: 0)
    /// The enlarger's exposure, in log10 lux-seconds at the paper.
    private(set) var exposure = 0.0
    /// Per-channel scale putting the Curve Set's reference neutral on Working Space
    /// mid-grey. What survives it is the paper's dyes and its curve, not a white
    /// balance the datasheet never published.
    private(set) var viewingScale = SIMD3<Double>(repeating: 1)

    init(directory: URL, basis: SpectralBasis) throws {
        let grid = basis.grid
        let sensitivities = try SpectralTable(directory, "sensitivity.csv", header: "wavelengthNM,red,green,blue").rows
        let dyeDensities = try SpectralTable(directory, "dye-density.csv", header: "wavelengthNM,cyan,magenta,yellow").rows
        guard sensitivities.map({ $0[0] }) == grid, dyeDensities.map({ $0[0] }) == grid else {
            throw FilmError.invalid("The RA-4 paper's tables must share the Curve Set's own band grid")
        }
        // Peak-normalised as the chart draws them, which is what makes a filter
        // density a density at that filter's own peak.
        guard (1...3).allSatisfy({ column in dyeDensities.contains { abs($0[column] - 1) < 0.01 } }) else {
            throw FilmError.invalid("The RA-4 paper's dye curves must be peak-normalised")
        }
        sensitivity = sensitivities.enumerated().map { i, row in SIMD3(row[1], row[2], row[3]) * basis.quadrature(i) }
        dyes = dyeDensities.map { SIMD3($0[1], $0[2], $0[3]) }
        lamp = grid.enumerated().map { i, nm in Self.planck(nm, Self.lampKelvin) * basis.quadrature(i) }
        // `logExposure,red,green,blue` in one file: the paper's three layers are
        // measured together, unlike a Stock's, whose channels are separate CSVs.
        curves = try (1...3).map { try CharacteristicCurve(url: directory.appendingPathComponent("density.csv"),
                                                           columns: ["red", "green", "blue"], column: $0,
                                                           exposureRange: -10...10) }
        guard curves.allSatisfy({ curve in
            zip(curve.points, curve.points.dropFirst()).allSatisfy { $0.density <= $1.density }
        }) else { throw FilmError.invalid("The RA-4 paper's characteristic curves must be monotone") }
        let minima = curves.map { $0.points[0].density }
        minimumDensity = SIMD3(minima[0], minima[1], minima[2])
        base = (minima[0] + minima[1] + minima[2]) / 3
        // What the paper has to form for the aim to be a neutral rather than three
        // equal Status A numbers. The three dyes are not a visual neutral in equal
        // amounts, and a print whose mid-scale is Status A neutral would carry that
        // difference all the way to its paper white, where there is no dye left to
        // hide it. Solved instead: the amounts whose reflection is neutral at the
        // aim's own density, damped one channel at a time because each dye dominates
        // its own channel and their overlap is what the further steps are for.
        let observerXYZ = basis.observerXYZ
        let xyzToRGB = SpectralBasis.rgbToXYZ.inverse
        let paperBase = base, paperDyes = dyes
        func reflect(_ amounts: SIMD3<Double>) -> SIMD3<Double> {
            var xyz = SIMD3<Double>(repeating: 0)
            for i in paperDyes.indices { xyz += observerXYZ[i] * pow(10, -(paperBase + simd_dot(paperDyes[i], amounts))) }
            return xyzToRGB * xyz
        }
        // A perfect diffuser under the same Viewing Light: neutral, because the
        // Working Space white and the observer's illuminant are the same one.
        let diffuser = xyzToRGB * observerXYZ.reduce(SIMD3<Double>(repeating: 0), +)
        let target = diffuser * pow(10, -Self.aimDensity)
        var amounts = SIMD3<Double>(repeating: Self.aimDensity)
        for _ in 0..<128 {
            let reflected = reflect(amounts)
            guard reflected.min() > 0 else { throw FilmError.invalid("The RA-4 paper's aim does not reflect") }
            for c in 0..<3 { amounts[c] += log10(reflected[c] / target[c]) }
        }
        guard simd_reduce_max(simd_abs(reflect(amounts) / target - SIMD3(repeating: 1))) < 1e-9 else {
            throw FilmError.invalid("The RA-4 paper's dyes do not reach a neutral at its aim density")
        }
        var aims = SIMD3<Double>(repeating: 0)
        for layer in 0..<3 {
            guard amounts[layer] > 0,
                  let logH = Self.solve(curves[layer], for: minimumDensity[layer] + amounts[layer]) else {
                throw FilmError.invalid("The RA-4 paper does not reach a neutral at its aim density")
            }
            aims[layer] = logH
        }
        aim = aims
    }

    /// Spectral radiance of a Planckian radiator, in arbitrary units: only the shape
    /// matters, because the exposure solve absorbs any overall scale.
    private static func planck(_ nm: Double, _ kelvin: Double) -> Double {
        let metres = nm * 1e-9
        return 1 / (pow(metres, 5) * (exp(0.014387769 / (metres * kelvin)) - 1))
    }

    /// Where a monotone curve first reaches `density`, or nil when it never does.
    private static func solve(_ curve: CharacteristicCurve, for density: Double) -> Double? {
        guard curve.points[0].density <= density,
              let index = curve.points.indices.dropFirst().first(where: { curve.points[$0].density >= density })
        else { return nil }
        let low = curve.points[index - 1], high = curve.points[index]
        guard high.density > low.density else { return low.logExposure }
        let weight = (density - low.density) / (high.density - low.density)
        return low.logExposure + weight * (high.logExposure - low.logExposure)
    }

    /// The log10 exposure each paper layer receives from a negative of these dye
    /// amounts, under the current filter pack and enlarger exposure.
    private func layerExposure(_ amounts: SIMD3<Double>, negative: SpectralModel) -> SIMD3<Double> {
        var received = SIMD3<Double>(repeating: 0)
        for i in dyes.indices {
            let negativeDensity = negative.minimumDensity[i] + simd_dot(negative.dyeContributions[i], amounts)
            let filterDensity = simd_dot(dyes[i], filtration)
            received += sensitivity[i] * lamp[i] * pow(10, -(negativeDensity + filterDensity))
        }
        return SIMD3(log10(max(received.x, 1e-30)), log10(max(received.y, 1e-30)), log10(max(received.z, 1e-30))) + exposure
    }

    /// Sets the filter pack and the exposure so the Curve Set's own reference neutral
    /// prints on the paper's aim, then the viewing scale so it lands on Working Space
    /// mid-grey. This is a printer's ring-around, done once per Development Offset's
    /// Colour Cube rather than per frame.
    ///
    /// A filter's density subtracts from its own layer's log exposure almost one for
    /// one, so the fixed point converges in a handful of steps; the dyes' overlap is
    /// what the remaining iterations are for. Splitting each step into the pack's
    /// colour and its neutral density is what keeps the pack's three components
    /// summing to zero.
    mutating func balance(against negative: SpectralModel, offset: Double) throws {
        let neutral = negative.dyeAmounts(negative.density(negative.referenceExposure, offset: offset))
        for _ in 0..<128 {
            let error = layerExposure(neutral, negative: negative) - aim
            let common = (error.x + error.y + error.z) / 3
            exposure -= common
            filtration += error - SIMD3(repeating: common)
        }
        let residual = layerExposure(neutral, negative: negative) - aim
        guard simd_reduce_max(simd_abs(residual)) < 1e-6 else {
            throw FilmError.invalid("The enlarger cannot balance this Stock's reference neutral onto the paper's aim")
        }
        viewingScale = SIMD3(repeating: 1)
        let printed = print(negative.density(negative.referenceExposure, offset: offset), negative: negative)
        guard printed.min() > 0 else { throw FilmError.invalid("The reference neutral does not print") }
        viewingScale = SIMD3(repeating: 0.18) / printed
    }

    /// The print of one negative density, in the Working Space.
    ///
    /// Not clamped above one, for the reason a Transparency is not: paper white is
    /// brighter than mid-grey — about three stops on this paper — and the Working
    /// Space carries that exactly as it carries any other highlight. Clipping to a
    /// delivery range is the file writer's job.
    func print(_ density: SIMD3<Double>, negative: SpectralModel) -> SIMD3<Double> {
        let logH = layerExposure(negative.dyeAmounts(density), negative: negative)
        var amounts = SIMD3<Double>(repeating: 0)
        for layer in 0..<3 {
            amounts[layer] = max(0, curves[layer].density(atLinearExposure: pow(10, logH[layer])) - minimumDensity[layer])
        }
        var xyz = SIMD3<Double>(repeating: 0)
        for i in dyes.indices {
            xyz += negative.observerXYZ[i] * pow(10, -(base + simd_dot(dyes[i], amounts)))
        }
        return simd_max(negative.xyzToRGB * xyz * viewingScale, SIMD3(repeating: 0))
    }
}
