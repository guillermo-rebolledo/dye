import Foundation
import simd

/// White Balance: the user's temperature and tint name the Scene Illuminant; the
/// Stock Balance is the illuminant the Stock renders as neutral. Decoded photos
/// already show a neutral grey as neutral, so the pass re-illuminates the scene
/// with the Scene Illuminant and adapts from the Stock Balance, a von Kries
/// scaling in Bradford cone space. Matching illuminants give exact identity.
enum WhiteBalance {
    static let rec2020ToXYZ = simd_double3x3(rows: [
        SIMD3(0.636958, 0.144617, 0.168881),
        SIMD3(0.262700, 0.677998, 0.059302),
        SIMD3(0.000000, 0.028073, 1.060985)])
    static let bradford = simd_double3x3(rows: [
        SIMD3(0.8951, 0.2664, -0.1614),
        SIMD3(-0.7502, 1.7135, 0.0367),
        SIMD3(0.0389, -0.0685, 1.0296)])

    /// Nil means the pass is an exact pass-through.
    static func matrix(sceneKelvin: Double, tint: Double, stockBalanceKelvin: Double) -> simd_float3x3? {
        if sceneKelvin == stockBalanceKelvin && tint == 0 { return nil }
        let scene = bradford * illuminant(kelvin: sceneKelvin, deltaUV: -tint * 0.0005)
        let stock = bradford * illuminant(kelvin: stockBalanceKelvin, deltaUV: 0)
        let scale = simd_double3x3(diagonal: scene / stock)
        let m = rec2020ToXYZ.inverse * bradford.inverse * scale * bradford * rec2020ToXYZ
        return simd_float3x3(columns: (SIMD3<Float>(m.columns.0), SIMD3<Float>(m.columns.1), SIMD3<Float>(m.columns.2)))
    }

    /// XYZ with Y = 1 for a Planckian radiator (Kim et al. 2002 approximation,
    /// 1667...25000 K) displaced by `deltaUV` perpendicular to the locus in CIE 1960
    /// (u, v); positive is above the locus, toward green.
    static func illuminant(kelvin: Double, deltaUV: Double) -> SIMD3<Double> {
        var uv = planckianUV(kelvin)
        if deltaUV != 0 {
            let step = kelvin * 0.01
            let tangent = simd_normalize(planckianUV(min(kelvin + step, 25000)) - planckianUV(max(kelvin - step, 1667)))
            var normal = SIMD2(-tangent.y, tangent.x)
            if normal.y < 0 { normal = -normal }
            uv += normal * deltaUV
        }
        let denominator = 2 * uv.x - 8 * uv.y + 4
        let x = 3 * uv.x / denominator
        let y = 2 * uv.y / denominator
        return SIMD3(x / y, 1, (1 - x - y) / y)
    }

    static func planckianUV(_ kelvin: Double) -> SIMD2<Double> {
        let t = min(max(kelvin, 1667), 25000)
        let x: Double
        if t <= 4000 { x = -0.2661239e9 / (t * t * t) - 0.2343589e6 / (t * t) + 0.8776956e3 / t + 0.179910 }
        else { x = -3.0258469e9 / (t * t * t) + 2.1070379e6 / (t * t) + 0.2226347e3 / t + 0.240390 }
        let y: Double
        if t <= 2222 { y = -1.1063814 * x * x * x - 1.34811020 * x * x + 2.18555832 * x - 0.20219683 }
        else if t <= 4000 { y = -0.9549476 * x * x * x - 1.37418593 * x * x + 2.09137015 * x - 0.16748867 }
        else { y = 3.0817580 * x * x * x - 5.87338670 * x * x + 3.75112997 * x - 0.37001483 }
        let denominator = -2 * x + 12 * y + 3
        return SIMD2(4 * x / denominator, 6 * y / denominator)
    }
}
