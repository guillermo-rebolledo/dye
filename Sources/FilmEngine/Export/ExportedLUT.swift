import Foundation
import simd

extension Renderer {
    /// The colour half of a look as a `.cube` **Exported LUT**.
    ///
    /// This falls out of MEM-239's tier split rather than being modelled separately:
    /// everything that is a pure per-pixel colour mapping — White Balance, Exposure,
    /// the Film Response and its Development Offset blend, the Output Stage, the
    /// Adjustment Pass and the Output Transform — is exactly what a cube can carry, and everything the runtime
    /// keeps for itself is exactly what it cannot. So the LUT is *rendered*, through
    /// the same shaders and the same Plan as a photograph, with the spatial Passes
    /// off. Nothing here reimplements the look, which is why it cannot drift from it.
    ///
    /// What that leaves out is Halation, Bloom, Grain, the Stock's MTF and the Geometry
    /// Pass. A LUT is a function of one pixel's colour; none of those five is. Users
    /// have to be told, or the LUT looking flatter than the app reads as a bug — the
    /// header below says so and so does the export UI.
    ///
    /// The lattice is addressed in the same encoding the LUT returns, so it drops into
    /// a grade of already-display-encoded footage. `DOMAIN_MAX` is 1: input outside
    /// that is not addressable by a cube, and the app's own render is where scene
    /// values above diffuse white still live.
    public func exportedLUT(profile: Profile, settings: RenderSettings = .init(), size: Int = 33) async throws -> String {
        guard (2...65).contains(size) else { throw FilmError.invalid("Exported LUT size must be 2...65") }
        guard settings.output != .workingSpace else {
            throw FilmError.invalid("An Exported LUT needs a display encoding; choose Display P3 or sRGB")
        }
        try settings.validate()
        // Red varies fastest, as `.cube` requires and as the Colour Cube payload does.
        // The lattice is laid out as a wide, short image purely so it is one render.
        let width = size * size, height = size
        var rgba = [Float16](repeating: 0, count: width * height * 4)
        for blue in 0..<size {
            for green in 0..<size {
                for red in 0..<size {
                    let address = SIMD3<Double>(Double(red), Double(green), Double(blue)) / Double(size - 1)
                    let light = OutputTransform.workingSpace(address, from: settings.output)
                    let index = (red + size * (green + size * blue)) * 4
                    rgba[index] = Float16(light.x)
                    rgba[index + 1] = Float16(light.y)
                    rgba[index + 2] = Float16(light.z)
                    rgba[index + 3] = 1
                }
            }
        }
        let lattice = try await texture(for: .linear(LinearImage(unchecked: width, height, rgba)))
        let scratch = try decoder.makeTexture(width: width, height: height)
        let rendered = try readback(await renderTile(lattice, into: scratch, frame: Frame(width: width, height: height),
                                                     profile: profile, settings: settings, queue: exportQueue, spatial: false))
        let header = """
        # Exported from Dye: \(profile.metadata.displayName), \(settings.output.displayName).
        # Colour only. This LUT carries no grain, halation, bloom, micro-contrast
        # or vignette, so it will look flatter than the app does.
        TITLE "\(title(profile: profile, settings: settings))"
        LUT_3D_SIZE \(size)
        DOMAIN_MIN 0.0 0.0 0.0
        DOMAIN_MAX 1.0 1.0 1.0


        """
        // Six decimal places, formatted as integers rather than through
        // `String(format:)`. At the default lattice that is 107 811 `CVarArg` bridges
        // and as many intermediate arrays and joined strings; at the largest it is
        // 823 875. The digits are the same digits — `theExportedLUTTextIsByteIdentical`
        // is what says so — and the whole file is built into one byte buffer, off the
        // renderer actor, since only the lattice render needs the Renderer at all.
        let entries = size * size * size
        var text = Array(header.utf8)
        text.reserveCapacity(text.count + entries * 27)
        for entry in 0..<entries {
            let index = entry * 4
            for channel in 0..<3 {
                if channel > 0 { text.append(UInt8(ascii: " ")) }
                append(Double(rendered.rgba[index + channel]), to: &text)
            }
            text.append(UInt8(ascii: "\n"))
        }
        return String(decoding: text, as: UTF8.self)
    }

    /// `%.6f` for the values a rendered lattice holds, without the bridge.
    ///
    /// Two details are what make this the same six digits rather than nearly them.
    ///
    /// `%f` rounds an exact tie to even, not away from zero, and a rendered lattice
    /// produces ties constantly: every value is a `Float16`, so 0.0078125 scaled by a
    /// million is exactly 7812.5 and `%.6f` writes `0.007812`. Thirty-two of the
    /// half values below one land on a tie. Scaling by a million is itself exact for
    /// every `Float16` — eleven mantissa bits and the fourteen that 5⁶ needs is
    /// twenty-five, well inside a `Double` — so rounding to even here is not an
    /// approximation of what `%f` does; it is the same decision on the same number.
    ///
    /// And a negative keeps its sign even when it rounds to zero. A display encoding
    /// of a colour outside the gamut is negative, and `-0.000000` is what `%.6f`
    /// writes for it.
    private func append(_ value: Double, to text: inout [UInt8]) {
        guard value.isFinite else {
            text.append(contentsOf: Array((value.isNaN ? "nan" : value < 0 ? "-inf" : "inf").utf8))
            return
        }
        let negative = value < 0 || (value == 0 && value.sign == .minus)
        let scaled = (abs(value) * 1_000_000).rounded(.toNearestOrEven)
        // Beyond this the fixed-point form cannot be held exactly in a `UInt64`, and a
        // rendered display encoding is nowhere near it.
        guard scaled < 1e18 else {
            text.append(contentsOf: Array(String(format: "%.6f", value).utf8))
            return
        }
        let whole = UInt64(scaled) / 1_000_000, fraction = UInt64(scaled) % 1_000_000
        if negative { text.append(UInt8(ascii: "-")) }
        append(whole, to: &text, minimumDigits: 1)
        text.append(UInt8(ascii: "."))
        append(fraction, to: &text, minimumDigits: 6)
    }

    private func append(_ value: UInt64, to text: inout [UInt8], minimumDigits: Int) {
        var digits = [UInt8]()
        var remaining = value
        repeat {
            digits.append(UInt8(ascii: "0") + UInt8(remaining % 10))
            remaining /= 10
        } while remaining > 0
        while digits.count < minimumDigits { digits.append(UInt8(ascii: "0")) }
        text.append(contentsOf: digits.reversed())
    }

    /// A name that says which Stock and which of the user's colour controls are in it,
    /// because a `.cube` in a folder of `.cube`s has nothing else to identify it by.
    private func title(profile: Profile, settings: RenderSettings) -> String {
        var parts = [profile.metadata.displayName]
        // A Contrast Filter is part of the colour half of the look and does travel in
        // a cube, unlike the five spatial Passes the header warns about.
        if settings.contrastFilter != .none { parts.append(settings.contrastFilter.displayName) }
        if abs(settings.developmentOffset) >= 0.05 {
            parts.append(String(format: "%@ %+.1f", settings.developmentOffset > 0 ? "push" : "pull", settings.developmentOffset))
        }
        if abs(settings.exposureStops) >= 0.05 { parts.append(String(format: "%+.1f EV", settings.exposureStops)) }
        if settings.temperatureKelvin != RenderSettings.defaultTemperatureKelvin || settings.tint != 0 {
            parts.append("\(Int(settings.temperatureKelvin.rounded())) K")
        }
        // The Adjustment Pass is per-pixel, so a cube carries it whole.
        if !settings.adjustments.isNeutral { parts.append("adjusted") }
        return parts.joined(separator: " · ")
    }
}
