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
public struct RenderSettings: Codable, Sendable, Equatable, Hashable {
    /// The encoding the render is delivered in. `workingSpace` is the linear
    /// Rec.2020 signal itself and is a diagnostic rather than a deliverable.
    public enum Output: UInt32, Codable, Sendable, CaseIterable {
        case workingSpace = 0, displayP3 = 1, sRGB = 2
        public var displayName: String {
            switch self { case .workingSpace: "Working space"; case .displayP3: "Display P3"; case .sRGB: "sRGB" }
        }
    }
    public var output: Output
    /// Scene Illuminant correlated colour temperature in kelvin, 1667...25000.
    public var temperatureKelvin: Double
    /// Offset perpendicular to the Planckian locus in CIE 1960 (u, v), in units of
    /// 0.0005 Δuv and limited to ±100. Positive is magenta, negative is green.
    public var tint: Double
    /// Scalar multiply in linear light, expressed in stops.
    public var exposureStops: Double
    /// How long the frame was exposed for. Only the Reciprocity Pass reads it, and
    /// only above the Stock's own threshold: this is not a second exposure control.
    public var exposureSeconds: Double
    /// Push or pull in stops. Pushing by one stop rates the Stock one stop faster
    /// (a −1 EV exposure offset) and develops with the +1 Colour Cube.
    public var developmentOffset: Double
    /// Coloured glass on the lens, multiplying the scene spectrally before the
    /// Monochrome Collapse. Black & white only: a colour Stock has no collapse for
    /// it to act on, and asking for one there is an error rather than a no-op.
    public var contrastFilter: ContrastFilter
    /// Halation scaled relative to the Profile's own strength: 1 is the Profile
    /// value, 0 disables the Pass. Above 1, strength increases and the highlight
    /// threshold falls; 2 is the maximum creative boost.
    public var halationIntensity: Double
    /// Bloom scaled relative to the Profile's own lens diffusion: 1 is the Profile
    /// value, 0 disables the Pass. Above 1, diffusion increases to a stronger
    /// creative effect; 2 is the maximum boost.
    public var bloomIntensity: Double
    /// Grain scaled relative to the Profile's own granularity: 1 is the Profile
    /// value, 0 disables the Pass, 2 is the top of the user's 0–200% control.
    public var grainIntensity: Double
    /// Lens falloff added by the Geometry Pass. 0 is off; 1 costs the corners two stops.
    public var vignette: Double
    /// How unsteadily the frame sat in the gate, 0...1 of the full excursion. The
    /// displacement itself is fixed by `seed`, so a still frame does not shimmer.
    public var gateWeave: Double
    /// The unexposed rebate around the frame, 0...1 of its full width.
    public var frameBorder: Double
    /// Tone and colour work done to the scan afterwards, the way a photo editor
    /// does it. Per-pixel and after the Output Stage, so nothing here reaches the
    /// film; all eight default to zero, where the Pass is an exact pass-through.
    public var adjustments: Adjustments
    /// Fixes the Grain field and the gate weave displacement. The same seed renders
    /// the same frame, which is what makes Golden Images possible with Grain on.
    public var seed: UInt32
    /// Nil follows the Profile. `none` returns Density Space for Density Space
    /// Colour Cubes and is how Step Wedges read measured density.
    public var outputStage: OutputStage?

    public static let defaultTemperatureKelvin = 5500.0
    public static let temperatureRange = 1667.0...25000.0
    public static let tintRange = -100.0...100.0
    public static let exposureRange = -6.0...6.0
    /// A thirtieth of a millisecond to an hour: the range a camera and a cable
    /// release between them can reach, which is where reciprocity failure lives.
    public static let exposureSecondsRange = 1.0 / 8000...3600.0
    public static let defaultExposureSeconds = 1.0 / 125
    public static let developmentRange = -3.0...3.0
    public static let halationRange = 0.0...2.0
    public static let bloomRange = 0.0...2.0
    public static let grainRange = 0.0...2.0
    public static let vignetteRange = 0.0...1.0
    public static let gateWeaveRange = 0.0...1.0
    public static let frameBorderRange = 0.0...1.0

    public init(output: Output = .displayP3, temperatureKelvin: Double = RenderSettings.defaultTemperatureKelvin, tint: Double = 0,
                exposureStops: Double = 0, exposureSeconds: Double = RenderSettings.defaultExposureSeconds,
                developmentOffset: Double = 0, contrastFilter: ContrastFilter = .none,
                halationIntensity: Double = 1,
                bloomIntensity: Double = 1, grainIntensity: Double = 1, vignette: Double = 0, gateWeave: Double = 0, frameBorder: Double = 0,
                adjustments: Adjustments = Adjustments(), seed: UInt32 = 0, outputStage: OutputStage? = nil) {
        self.output = output
        self.temperatureKelvin = temperatureKelvin
        self.tint = tint
        self.exposureStops = exposureStops
        self.exposureSeconds = exposureSeconds
        self.developmentOffset = developmentOffset
        self.contrastFilter = contrastFilter
        self.halationIntensity = halationIntensity
        self.bloomIntensity = bloomIntensity
        self.grainIntensity = grainIntensity
        self.vignette = vignette
        self.gateWeave = gateWeave
        self.frameBorder = frameBorder
        self.adjustments = adjustments
        self.seed = seed
        self.outputStage = outputStage
    }

    /// Every key but the exposure time, the Contrast Filter and the Adjustments is
    /// required. All three arrived after Presets were already being written, and a
    /// saved Preset that predates them means a frame nobody recorded a shutter speed
    /// for, no glass on the lens and a scan nobody touched, not a broken Preset.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        output = try values.decode(Output.self, forKey: .output)
        temperatureKelvin = try values.decode(Double.self, forKey: .temperatureKelvin)
        tint = try values.decode(Double.self, forKey: .tint)
        exposureStops = try values.decode(Double.self, forKey: .exposureStops)
        exposureSeconds = try values.decodeIfPresent(Double.self, forKey: .exposureSeconds) ?? Self.defaultExposureSeconds
        developmentOffset = try values.decode(Double.self, forKey: .developmentOffset)
        contrastFilter = try values.decodeIfPresent(ContrastFilter.self, forKey: .contrastFilter) ?? .none
        halationIntensity = try values.decode(Double.self, forKey: .halationIntensity)
        bloomIntensity = try values.decode(Double.self, forKey: .bloomIntensity)
        grainIntensity = try values.decode(Double.self, forKey: .grainIntensity)
        vignette = try values.decode(Double.self, forKey: .vignette)
        gateWeave = try values.decode(Double.self, forKey: .gateWeave)
        frameBorder = try values.decode(Double.self, forKey: .frameBorder)
        adjustments = try values.decodeIfPresent(Adjustments.self, forKey: .adjustments) ?? Adjustments()
        seed = try values.decode(UInt32.self, forKey: .seed)
        outputStage = try values.decodeIfPresent(OutputStage.self, forKey: .outputStage)
    }

    public func validate() throws {
        guard temperatureKelvin.isFinite, Self.temperatureRange.contains(temperatureKelvin) else {
            throw FilmError.invalid("Scene Illuminant temperature must be 1667...25000 K")
        }
        guard tint.isFinite, Self.tintRange.contains(tint) else { throw FilmError.invalid("Tint must be within ±100") }
        guard exposureStops.isFinite, Self.exposureRange.contains(exposureStops) else { throw FilmError.invalid("Exposure must be within ±6 stops") }
        guard exposureSeconds.isFinite, Self.exposureSecondsRange.contains(exposureSeconds) else {
            throw FilmError.invalid("Exposure time must be 1/8000...3600 seconds")
        }
        guard developmentOffset.isFinite, Self.developmentRange.contains(developmentOffset) else {
            throw FilmError.invalid("Development Offset must be within ±3 stops")
        }
        guard halationIntensity.isFinite, Self.halationRange.contains(halationIntensity) else {
            throw FilmError.invalid("Halation intensity must be 0...2")
        }
        guard bloomIntensity.isFinite, Self.bloomRange.contains(bloomIntensity) else {
            throw FilmError.invalid("Bloom intensity must be 0...2")
        }
        guard grainIntensity.isFinite, Self.grainRange.contains(grainIntensity) else {
            throw FilmError.invalid("Grain intensity must be 0...2")
        }
        guard vignette.isFinite, Self.vignetteRange.contains(vignette) else { throw FilmError.invalid("Vignette must be 0...1") }
        guard gateWeave.isFinite, Self.gateWeaveRange.contains(gateWeave) else { throw FilmError.invalid("Gate weave must be 0...1") }
        guard frameBorder.isFinite, Self.frameBorderRange.contains(frameBorder) else {
            throw FilmError.invalid("Frame border must be 0...1")
        }
        try adjustments.validate()
    }
}

/// The user's tone and colour controls over the scan, the ones a photo editor
/// offers: what is done to the picture *after* the film has had its say.
///
/// Every value is bipolar, −1…1, with zero meaning the control is not applied.
/// The app shows them as ±100. They act on the positive the Output Stage returns —
/// or on the Transparency, for a reversal Stock, or on the Working Space itself for
/// the identity Profile — and never on the light before the film, which is what
/// keeps Highlights from changing what the Emulsion recorded. Exposure, Temperature
/// and Tint are deliberately not here: they already exist as the Light controls,
/// and there they mean what they say.
///
/// The tone controls are applied per channel as one monotone curve in a display
/// encoding, so they cannot invert a gradient and a scene value above diffuse white
/// survives them; the colour controls act on chroma about Rec.2020 luminance.
public struct Adjustments: Codable, Sendable, Equatable, Hashable {
    /// Lifts the darker tones, pulls back the brighter ones and adds a little
    /// midtone contrast in one move, so detail reads without the picture going flat.
    public var brilliance: Double
    /// The brightest tones only. Negative recovers a highlight that is at or past
    /// white, positive pushes the brights up.
    public var highlights: Double
    /// The darkest tones only. Positive opens the shadows to reveal what the film
    /// kept there; negative closes them.
    public var shadows: Double
    /// The separation of light from dark about mid-grey, as an S-curve.
    public var contrast: Double
    /// The midtones, with black and white held where they are.
    public var brightness: Double
    /// Where black sits. Positive deepens the blacks by crushing the darkest
    /// tones into them; negative lifts them, the way a matte print does.
    public var blackPoint: Double
    /// Every colour's intensity equally. −1 is a neutral grey.
    public var saturation: Double
    /// Muted colours more than saturated ones, and skin tones least of all.
    public var vibrance: Double

    public static let range = -1.0...1.0

    public init(brilliance: Double = 0, highlights: Double = 0, shadows: Double = 0, contrast: Double = 0,
                brightness: Double = 0, blackPoint: Double = 0, saturation: Double = 0, vibrance: Double = 0) {
        self.brilliance = brilliance
        self.highlights = highlights
        self.shadows = shadows
        self.contrast = contrast
        self.brightness = brightness
        self.blackPoint = blackPoint
        self.saturation = saturation
        self.vibrance = vibrance
    }

    /// A Preset saved before one of these existed decodes it as not applied.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        brilliance = try values.decodeIfPresent(Double.self, forKey: .brilliance) ?? 0
        highlights = try values.decodeIfPresent(Double.self, forKey: .highlights) ?? 0
        shadows = try values.decodeIfPresent(Double.self, forKey: .shadows) ?? 0
        contrast = try values.decodeIfPresent(Double.self, forKey: .contrast) ?? 0
        brightness = try values.decodeIfPresent(Double.self, forKey: .brightness) ?? 0
        blackPoint = try values.decodeIfPresent(Double.self, forKey: .blackPoint) ?? 0
        saturation = try values.decodeIfPresent(Double.self, forKey: .saturation) ?? 0
        vibrance = try values.decodeIfPresent(Double.self, forKey: .vibrance) ?? 0
    }

    /// The controls in the order the app lists them, each with the name it shows.
    public var all: [(name: String, value: Double)] {
        [("Brilliance", brilliance), ("Highlights", highlights), ("Shadows", shadows), ("Contrast", contrast),
         ("Brightness", brightness), ("Black point", blackPoint), ("Saturation", saturation), ("Vibrance", vibrance)]
    }

    /// True when nothing is applied and the Pass has nothing to do.
    public var isNeutral: Bool { all.allSatisfy { $0.value == 0 } }

    public func validate() throws {
        for (name, value) in all {
            guard value.isFinite, Self.range.contains(value) else {
                throw FilmError.invalid("\(name) must be within ±1")
            }
        }
    }
}

/// Red varies fastest, then green, then blue. Each texel contains RGBA float16.
public struct ColourCube: Sendable, Equatable {
    public let size: Int
    public let rgba: [Float16]
    public init(size: Int, rgba: [Float16]) throws {
        guard (2...129).contains(size), rgba.count == size * size * size * 4,
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
    public func sample(_ coordinate: SIMD3<Double>) -> SIMD3<Double> {
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
    /// Copies retain identity so display-only changes need no pixel comparison or upload.
    public let id = UUID()
    public let width: Int
    public let height: Int
    public let rgba: [Float16]
    public let output: RenderSettings.Output
}
