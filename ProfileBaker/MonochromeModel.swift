import Foundation
import FilmEngine
import simd

/// The offline model behind a black & white Stock.
///
/// A monochrome Stock is not a colour Stock with the colour taken out, and it needs
/// no Colour Cube: one spectral sensitivity curve collapsing to one density channel
/// is both cheaper than a 33³ lookup and closer to what the film does. What makes
/// two panchromatic Stocks differ is *how they see colour* — the shape of that curve
/// — so the Spectral Weight is integrated from the published sensitivity against the
/// CIE colour matching functions rather than assumed from a luminance weighting.
///
/// A Contrast Filter is the same integral with the glass's transmittance inside it.
/// That is where a coloured filter physically acts: it multiplies the spectrum on the
/// way in, before the film sees it, which is why the model has to reach the spectrum
/// to express one at all and why a tint applied to the developed grey cannot.
struct MonochromeSpectralModel {
    let shaper: FilmProfile.LogExposureShaper
    let curve: CharacteristicCurve
    let densityCurveName: String
    /// Unnormalised, in the Stock's own published sensitivity units, so the ratio of
    /// two sums is a filter factor.
    let spectralWeight: SIMD3<Double>
    let filters: [(filter: ContrastFilter, weight: SIMD3<Double>)]
    let spectralContributions: [FilmProfile.Monochrome.SpectralContributions]

    /// The Contrast Filters, in the order the picker offers them.
    static let contrastFilters: [ContrastFilter] = ContrastFilter.allCases.filter { $0 != .none }

    init(curves: CurveSet) throws {
        guard let shaper = curves.metadata.colour.inputShaper, curves.metadata.process.isMonochrome,
              let monochrome = curves.metadata.monochrome else {
            throw FilmError.invalid("Missing spectral input shaper or Monochrome section")
        }
        self.shaper = shaper
        let requiredProvenance = ["spectral.characteristicCurve", "spectral.sensitivity", "spectral.observer",
                                  "spectral.reconstruction", "spectral.contrastFilters"]
        guard requiredProvenance.allSatisfy({ curves.metadata.provenance[$0] != nil }) else {
            throw FilmError.invalid("Missing spectral per-parameter Provenance")
        }
        guard monochrome.spectralWeight == nil, monochrome.contrastFilters == nil, monochrome.spectralContributions == nil else {
            throw FilmError.invalid("Spectral Weights are derived by the Baker, not authored in stock.json")
        }
        densityCurveName = monochrome.densityCurve
        curve = try curves.characteristicCurves(for: monochrome.densityCurve)[0]
        guard zip(curve.points, curve.points.dropFirst()).allSatisfy({ $0.density <= $1.density }),
              curve.points.first!.logExposure >= shaper.minimumLogExposure,
              curve.points.last!.logExposure <= shaper.maximumLogExposure else {
            throw FilmError.invalid("The Characteristic Curve must increase inside the input shaper")
        }
        let sensitivities = try SpectralTable(curves.directory, "sensitivity.csv", header: "wavelengthNM,sensitivity").rows
        let observer = try SpectralTable(curves.directory, "observer.csv", header: "wavelengthNM,x,y,z,illuminant").rows
        let basis = try SpectralBasis(observer: observer)
        let names = Self.contrastFilters.map(\.rawValue)
        let glass = try SpectralTable(curves.contrastFilterDirectory, "transmittance.csv",
                                      header: (["wavelengthNM"] + names).joined(separator: ",")).rows
        guard sensitivities.map({ $0[0] }) == basis.grid, glass.map({ $0[0] }) == basis.grid else {
            throw FilmError.invalid("Sensitivity and Contrast Filter tables must share the observer's band grid")
        }
        guard glass.allSatisfy({ $0.dropFirst().allSatisfy { (0...1).contains($0) } }) else {
            throw FilmError.invalid("Contrast Filter transmittance must be 0...1")
        }
        let mtf = try SpectralTable(curves.directory, "mtf.csv", header: "cyclesPerMM,response").rows
        let rms = try SpectralTable(curves.directory, "rms-granularity.csv", header: "density,rmsGranularity").rows
        guard mtf.map({ $0[0] }) == curves.metadata.mtf.cyclesPerMM, mtf.map({ $0[1] }) == curves.metadata.mtf.response,
              rms.count == 1, rms[0][0] == 1, rms[0][1] == curves.metadata.grain.rmsGranularity else {
            throw FilmError.invalid("MTF or RMS CSV does not match Profile metadata")
        }
        let sensitivity = sensitivities.map { $0[1] }
        spectralWeight = basis.weight(sensitivity: sensitivity)
        guard spectralWeight.min() >= 0, spectralWeight.sum() > 0 else {
            throw FilmError.invalid("The Spectral Weight of an unfiltered Stock must be nonnegative")
        }
        filters = Self.contrastFilters.enumerated().map { index, filter in
            let weight = basis.weight(sensitivity: sensitivity, transmittance: glass.map { $0[index + 1] })
            return (filter, weight)
        }
        guard filters.allSatisfy({ $0.weight.sum() > 0 }) else {
            throw FilmError.invalid("A Contrast Filter left the Stock with no response at all")
        }
        spectralContributions = ContrastFilter.allCases.map { filter in
            let column = names.firstIndex(of: filter.rawValue).map { $0 + 1 }
            let contributions = basis.grid.indices.map { i in
                basis.rgbToBasis.transpose * basis.lobes[i] * sensitivity[i] * basis.quadrature(i) * (column.map { glass[i][$0] } ?? 1)
            }
            let sum = contributions.reduce(SIMD3<Double>(repeating: 0), +).sum()
            return .init(filter: filter, coefficients: contributions.map { [$0.x / sum, $0.y / sum, $0.z / sum] })
        }
    }

    /// The 1024-entry Density Curve, addressed by the input shaper's coordinate so a
    /// B&W Profile reads its curve in the same physical log exposure a colour one does.
    var densityCurve: Data {
        var bytes = Data(capacity: 2048)
        for i in 0..<1024 {
            let logH = shaper.minimumLogExposure + Double(i) / 1023 * (shaper.maximumLogExposure - shaper.minimumLogExposure)
            let bits = Float16(curve.density(atLinearExposure: pow(10, logH))).bitPattern
            bytes.append(UInt8(truncatingIfNeeded: bits))
            bytes.append(UInt8(truncatingIfNeeded: bits >> 8))
        }
        return bytes
    }

    /// Every weight is divided by the unfiltered sum, so the Stock's own weights add
    /// to one and each Contrast Filter's add to the reciprocal of its filter factor.
    /// The Stock's published sensitivity units cancel and what is left is the two
    /// things the runtime and the validator actually read.
    var monochrome: FilmProfile.Monochrome {
        let scale = 1 / spectralWeight.sum()
        func components(_ weight: SIMD3<Double>) -> [Double] {
            [weight.x * scale, weight.y * scale, weight.z * scale]
        }
        var result = FilmProfile.Monochrome(
            spectralWeight: components(spectralWeight),
            densityCurve: densityCurveName,
            contrastFilters: filters.map {
                FilmProfile.Monochrome.FilterWeight(filter: $0.filter, spectralWeight: components($0.weight))
            })
        result.spectralContributions = spectralContributions
        return result
    }
}

private extension SIMD3 where Scalar == Double {
    func sum() -> Double { x + y + z }
}
