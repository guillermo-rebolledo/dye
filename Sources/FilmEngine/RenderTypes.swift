import Foundation
import simd

public enum FilmError: Error, LocalizedError, Sendable {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
}

/// Straight-alpha RGBA, linear Rec.2020, stored at the pipeline's float16 precision.
public struct LinearImage: Sendable {
    public let width: Int
    public let height: Int
    public let rgba: [Float16]

    public init(width: Int, height: Int, rgba: [Float16]) throws {
        guard width > 0, height > 0, width <= 16_384, height <= 16_384,
              rgba.count == width * height * 4, rgba.allSatisfy(\.isFinite) else {
            throw FilmError.invalid("Invalid image dimensions or non-finite pixels")
        }
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    /// Renderer output: dimensions come from a texture and values are already float16.
    init(unchecked width: Int, _ height: Int, _ rgba: [Float16]) {
        self.width = width
        self.height = height
        self.rgba = rgba
    }
}

public enum RenderImage: Sendable {
    case linear(LinearImage)
    case encoded(Data)
}

/// The user's controls, in pipeline order. White Balance and Exposure act on the
/// light before the Film Response; the Development Offset selects and blends the
/// baked Colour Cubes and, as on a pushed roll, rates the Stock faster.
public struct RenderSettings: Sendable, Equatable, Hashable {
    public enum Output: UInt32, Sendable { case workingSpace = 0, displayP3 = 1 }
    public var output: Output
    /// Scene Illuminant correlated colour temperature in kelvin, 1667...25000.
    public var temperatureKelvin: Double
    /// Offset perpendicular to the Planckian locus in CIE 1960 (u, v), in units of
    /// 0.0005 Δuv and limited to ±100. Positive is magenta, negative is green.
    public var tint: Double
    /// Scalar multiply in linear light, expressed in stops.
    public var exposureStops: Double
    /// Push or pull in stops. Pushing by one stop rates the Stock one stop faster
    /// (a −1 EV exposure offset) and develops with the +1 Colour Cube.
    public var developmentOffset: Double
    /// Halation scaled relative to the Profile's own strength: 1 is the Profile
    /// value, 0 disables the Pass, 2 is the top of the user's 0–200% control.
    public var halationIntensity: Double
    /// Nil follows the Profile. `none` returns Density Space for Density Space
    /// Colour Cubes and is how Step Wedges read measured density.
    public var outputStage: OutputStage?

    public static let defaultTemperatureKelvin = 5500.0
    public static let temperatureRange = 1667.0...25000.0
    public static let tintRange = -100.0...100.0
    public static let exposureRange = -6.0...6.0
    public static let developmentRange = -3.0...3.0
    public static let halationRange = 0.0...2.0

    public init(output: Output = .displayP3, temperatureKelvin: Double = RenderSettings.defaultTemperatureKelvin, tint: Double = 0,
                exposureStops: Double = 0, developmentOffset: Double = 0, halationIntensity: Double = 1, outputStage: OutputStage? = nil) {
        self.output = output
        self.temperatureKelvin = temperatureKelvin
        self.tint = tint
        self.exposureStops = exposureStops
        self.developmentOffset = developmentOffset
        self.halationIntensity = halationIntensity
        self.outputStage = outputStage
    }

    public func validate() throws {
        guard temperatureKelvin.isFinite, Self.temperatureRange.contains(temperatureKelvin) else {
            throw FilmError.invalid("Scene Illuminant temperature must be 1667...25000 K")
        }
        guard tint.isFinite, Self.tintRange.contains(tint) else { throw FilmError.invalid("Tint must be within ±100") }
        guard exposureStops.isFinite, Self.exposureRange.contains(exposureStops) else { throw FilmError.invalid("Exposure must be within ±6 stops") }
        guard developmentOffset.isFinite, Self.developmentRange.contains(developmentOffset) else {
            throw FilmError.invalid("Development Offset must be within ±3 stops")
        }
        guard halationIntensity.isFinite, Self.halationRange.contains(halationIntensity) else {
            throw FilmError.invalid("Halation intensity must be 0...2")
        }
    }
}

/// Red varies fastest, then green, then blue. Each texel contains RGBA float16.
public struct ColourCube: Sendable, Equatable {
    public let size: Int
    public let rgba: [Float16]
    public init(size: Int, rgba: [Float16]) throws {
        guard (2...65).contains(size), rgba.count == size * size * size * 4,
              rgba.allSatisfy(\.isFinite) else { throw FilmError.invalid("Invalid Colour Cube") }
        self.size = size
        self.rgba = rgba
    }
    public static let identity: ColourCube = {
        let size = 33
        var rgba: [Float16] = []
        for b in 0..<size { for g in 0..<size { for r in 0..<size {
            rgba += [Float16(r) / 32, Float16(g) / 32, Float16(b) / 32, 1]
        } } }
        return try! ColourCube(size: size, rgba: rgba)
    }()

    /// Tetrahedral interpolation of a coordinate already inside [0, 1]; the shader
    /// samples identically. The renderer uses this for the scan's auto-balance.
    func sample(_ coordinate: SIMD3<Double>) -> SIMD3<Double> {
        let q = simd_clamp(coordinate, SIMD3(repeating: 0), SIMD3(repeating: 1)) * Double(size - 1)
        var base = SIMD3<Int>(Int(q.x), Int(q.y), Int(q.z))
        base = simd_clamp(base, SIMD3(repeating: 0), SIMD3(repeating: size - 2))
        let f = q - SIMD3<Double>(Double(base.x), Double(base.y), Double(base.z))
        var order = [0, 1, 2]
        if f[order[0]] < f[order[1]] { order.swapAt(0, 1) }
        if f[order[1]] < f[order[2]] { order.swapAt(1, 2) }
        if f[order[0]] < f[order[1]] { order.swapAt(0, 1) }
        func texel(_ v: SIMD3<Int>) -> SIMD3<Double> {
            let index = ((v.z * size + v.y) * size + v.x) * 4
            return SIMD3(Double(rgba[index]), Double(rgba[index + 1]), Double(rgba[index + 2]))
        }
        var v1 = base; v1[order[0]] += 1
        var v2 = v1; v2[order[1]] += 1
        let x0 = texel(base), x1 = texel(v1), x2 = texel(v2), x3 = texel(base &+ 1)
        return x0 + f[order[0]] * (x1 - x0) + f[order[1]] * (x2 - x1) + f[order[2]] * (x3 - x2)
    }
}

/// Pixels returned by the renderer, tagged with the requested output encoding.
public struct RenderedPixels: Sendable {
    public let width: Int
    public let height: Int
    public let rgba: [Float16]
    public let output: RenderSettings.Output
}
