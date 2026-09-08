import Foundation

/// Shared, deterministic reference for perceptual review and Golden Images.
/// Includes saturated patches, fine detail, shadows, and lights above SDR white.
public enum ContactSheetReference {
    public static let settings = RenderSettings(vignette: 0.2, gateWeave: 0.3, frameBorder: 0.3, seed: 253)

    public static func image() throws -> LinearImage {
        let width = 192, height = 128
        let patches: [[Float]] = [[1, 0.08, 0.03], [0.05, 1, 0.12], [0.03, 0.1, 1],
                                  [0.6, 0.3, 0.18], [0.1, 0.5, 0.6], [1, 1, 1]]
        var rgba: [Float16] = []
        for y in 0..<height {
            for x in 0..<width {
                let ramp = pow(Float(2), Float(x) / Float(width - 1) * 12 - 9)
                let patch = patches[min(x / 32, patches.count - 1)]
                let value: [Float]
                if y < 40 { value = [ramp, ramp, ramp] }
                else if y < 88 { value = patch.map { $0 * (y < 64 ? 0.18 : 1) } }
                else {
                    let light: Float = (x - 144) * (x - 144) + (y - 106) * (y - 106) < 36 ? 8 : 0.02
                    let detail: Float = x < 96 && (x + y) % 4 < 2 ? 0.3 : light
                    value = [detail, detail, detail]
                }
                rgba.append(contentsOf: value.map(Float16.init)); rgba.append(1)
            }
        }
        return try LinearImage(width: width, height: height, rgba: rgba)
    }
}
