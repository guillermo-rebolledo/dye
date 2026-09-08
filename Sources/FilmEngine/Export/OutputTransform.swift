import Foundation
import simd

/// The inverse of the Output Transform: display encoding back to the Working Space.
///
/// The forward direction lives in `outputTransform` in `Pipeline.metal` and is the
/// only place a render passes through. This is its inverse, and it exists for one
/// caller: an Exported LUT is addressed by display-encoded values, so building its
/// lattice means asking what Working Space light each of those addresses stands for
/// and rendering *that*. The primaries below are the inverses of the shader's, and
/// the round trip is asserted through the renderer rather than trusted.
enum OutputTransform {
    /// The sRGB transfer function's inverse, applied through the sign so a negative
    /// out-of-gamut value survives the round trip the way the shader's does.
    static func decode(_ value: Double) -> Double {
        let magnitude = abs(value)
        let linear = magnitude <= 0.04045 ? magnitude / 12.92 : pow((magnitude + 0.055) / 1.055, 2.4)
        return value < 0 ? -linear : linear
    }

    /// Display P3 and sRGB share the transfer function above and differ only here.
    static func primaries(_ output: RenderSettings.Output) -> simd_double3x3 {
        switch output {
        case .workingSpace: matrix_identity_double3x3
        case .displayP3: simd_double3x3(rows: [SIMD3(0.7538330, 0.1985974, 0.0475696),
                                               SIMD3(0.0457439, 0.9417772, 0.0124789),
                                               SIMD3(-0.0012103, 0.0176017, 0.9836086)])
        case .sRGB: simd_double3x3(rows: [SIMD3(0.6274039, 0.3292830, 0.0433131),
                                          SIMD3(0.0690973, 0.9195404, 0.0113623),
                                          SIMD3(0.0163915, 0.0880133, 0.8955952)])
        }
    }

    /// One display-encoded value as the Working Space light it stands for.
    static func workingSpace(_ encoded: SIMD3<Double>, from output: RenderSettings.Output) -> SIMD3<Double> {
        guard output != .workingSpace else { return encoded }
        return primaries(output) * SIMD3(decode(encoded.x), decode(encoded.y), decode(encoded.z))
    }
}
