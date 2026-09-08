import Foundation
import FilmEngine
import simd

/// The colourimetric reconstruction basis both spectral branches share.
///
/// RGB does not determine a spectrum, so the model picks one: three smooth
/// nonnegative lobes illuminated by the observer's own illuminant, whose 3×3
/// transform is solved by integrating the lobes against the CIE colour matching
/// functions and normalising the truncated visible white to the Working Space
/// white. Once that transform exists, "integrate a film's spectral sensitivity
/// against CIE colour matching functions" has a single answer, and it is the same
/// answer for a Colour Cube's layer exposures and for a Monochrome Collapse.
struct SpectralBasis {
    /// Wavelengths in nanometres, uniformly spaced and common to every spectral table.
    let grid: [Double]
    /// Per band, how much each Working Space primary's reconstruction contributes.
    let lobes: [SIMD3<Double>]
    /// Linear Rec.2020 to basis coefficients.
    let rgbToBasis: simd_double3x3

    /// The Working Space primaries. Rec.2020 to CIE XYZ under D65, column-major.
    static let rgbToXYZ = simd_double3x3(columns: (SIMD3(0.636958, 0.262700, 0),
                                                   SIMD3(0.144617, 0.677998, 0.028073),
                                                   SIMD3(0.168881, 0.059302, 1.060985)))

    /// Trapezoidal weight for a band: the endpoints of a closed interval count half.
    func quadrature(_ index: Int) -> Double { (index == 0 || index == grid.count - 1) ? 0.5 : 1 }

    init(observer: [[Double]]) throws {
        let grid = observer.map { $0[0] }
        guard (31...81).contains(grid.count), grid.first == 400, grid.last == 700,
              zip(grid, grid.dropFirst()).allSatisfy({ abs(($1 - $0) - 300 / Double(grid.count - 1)) < 0.00001 }),
              observer.allSatisfy({ $0[4] > 0 }) else {
            throw FilmError.invalid("Spectral tables require a common uniform 31–81 band grid from 400 to 700 nm")
        }
        func gaussian(_ nm: Double, _ peak: Double, _ width: Double) -> Double { exp(-0.5 * pow((nm - peak) / width, 2)) }
        func quadrature(_ index: Int) -> Double { (index == 0 || index == grid.count - 1) ? 0.5 : 1 }
        let lobes = observer.map { row -> SIMD3<Double> in
            let shape = SIMD3(gaussian(row[0], 650, 45), gaussian(row[0], 540, 35), gaussian(row[0], 450, 30))
            return shape / (shape.x + shape.y + shape.z) * row[4]
        }
        self.grid = grid
        self.lobes = lobes
        // CIE integration gives this smooth spectral basis a colourimetric Rec.2020 input.
        // Normalize the truncated observer white to D65; saturated out-of-spectral-gamut
        // inputs are projected to nonnegative spectra after solving the basis coefficients.
        let rgbToXYZ = Self.rgbToXYZ
        var basisToXYZ = simd_double3x3(0)
        for i in grid.indices {
            let xyz = SIMD3(observer[i][1], observer[i][2], observer[i][3]) * quadrature(i)
            for c in 0..<3 { basisToXYZ[c] += xyz * lobes[i][c] }
        }

        let white = basisToXYZ * SIMD3<Double>(repeating: 1)
        guard (0..<3).allSatisfy({ white[$0] > 0 }) else { throw FilmError.invalid("Observer has no white response") }
        let whiteScale = (rgbToXYZ * SIMD3<Double>(repeating: 1)) / white
        for c in 0..<3 { basisToXYZ[c] *= whiteScale }
        guard abs(simd_determinant(basisToXYZ)) > 1e-8 else { throw FilmError.invalid("Singular observer basis") }
        rgbToBasis = basisToXYZ.inverse * rgbToXYZ
    }

    /// The Working Space weighting a spectral sensitivity collapses light with.
    ///
    /// `sensitivity` is the film's own response per band and `transmittance` the glass
    /// in front of it, so the multiply happens in the spectral domain where a Contrast
    /// Filter physically acts. Because the reconstruction is linear in the basis
    /// coefficients, the whole integral collapses to one three-vector: applying the
    /// filter before the collapse and collapsing with this weight are the same thing.
    func weight(sensitivity: [Double], transmittance: [Double]? = nil) -> SIMD3<Double> {
        var raw = SIMD3<Double>(repeating: 0)
        for i in grid.indices {
            raw += lobes[i] * sensitivity[i] * quadrature(i) * (transmittance?[i] ?? 1)
        }
        return rgbToBasis.transpose * raw
    }
}
