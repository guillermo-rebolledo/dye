import Foundation

public enum FilmProcess: String, Codable, Sendable, CaseIterable {
    case c41, e6, bwSilver = "bw-silver", bwChromogenic = "bw-chromogenic", ecn2
    public var isMonochrome: Bool { self == .bwSilver || self == .bwChromogenic }
    public var displayName: String {
        switch self {
        case .c41: "Colour negative (C-41)"
        case .e6: "Reversal (E-6)"
        case .bwSilver: "Black & white silver"
        case .bwChromogenic: "Black & white chromogenic"
        case .ecn2: "Motion picture (ECN-2)"
        }
    }
}

public enum FilmFormat: String, Codable, Sendable {
    case film135 = "135", film120 = "120", sheet4x5 = "4x5"
    /// Nominal exposed frame width; 120 assumes a 6×6 frame, 4×5 the long edge.
    public var frameWidthMM: Double {
        switch self { case .film135: 36; case .film120: 56; case .sheet4x5: 120 }
    }
}

public enum Provenance: String, Codable, Sendable { case measured, artistic }
public enum OutputStage: String, Codable, Sendable { case scan, print, none }
public enum GrainModel: String, Codable, Sendable { case stochastic, procedural, dyeCloud = "dye-cloud" }

/// The JSON metadata schema; payload references are stable names inside the container.
/// `balance` is Stock Balance in kelvin, never the user's White Balance.
public struct FilmProfile: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var process: FilmProcess
    public var nominalISO: Double
    public var trueISO: Double
    public var balance: Double
    public var format: FilmFormat
    public var colour: Colour
    public var monochrome: Monochrome?
    public var grain: Grain
    public var halation: Halation
    public var mtf: MTF
    public var reciprocity: Reciprocity
    /// The Profile this one is derived from, when it models the same Emulsion rather
    /// than its own Curve Set. Lineage, not a physical parameter, so it has no marker.
    public var derivedFrom: String?
    /// Dotted schema paths, one marker per physical parameter (arrays count as one).
    public var provenance: [String: Provenance]

    public struct Colour: Codable, Equatable, Sendable {
        public var lutVariants: [Variant]
        public var lutSize: Int
        public var outputStage: OutputStage
        /// Nil retains the foundation profiles' linear [0, 1] input and Density Space output.
        public var inputShaper: LogExposureShaper?
        public var cubeOutput: CubeOutput?
        /// SHA-256 of the offline model version and its authoring inputs; nil in stock.json.
        public var sourceFingerprint: String?
    }
    public enum CubeOutput: String, Codable, Sendable { case density, displayLinearRec2020 }
    /// Offline Colour Cube coordinates. Runtime application is the MEM-244 integration gate.
    public struct LogExposureShaper: Codable, Equatable, Sendable {
        public var minimumLogExposure: Double
        public var maximumLogExposure: Double
        /// Physical log10 lux-seconds corresponding to scene-linear 0.18.
        public var middleGrayLogExposure: Double
    }
    public struct Variant: Codable, Equatable, Sendable {
        public var pushStops: Double
        public var lut: String
        public init(pushStops: Double, lut: String) { self.pushStops = pushStops; self.lut = lut }
    }
    public struct Monochrome: Codable, Equatable, Sendable {
        public var spectralWeight: [Double]
        public var densityCurve: String
    }
    public struct Grain: Codable, Equatable, Sendable {
        public var model: GrainModel
        public var rmsGranularity: Double
        public var grainRadiusMicrons: Double
        public var densityResponse: [Double]
        public var channelCorrelation: Double
        public var channelRadiusScale: [Double]
    }
    /// `strength` is the fraction of above-threshold light scattered back into the
    /// Emulsion, `threshold` the Working Space value the smooth knee is centred on,
    /// and `radiusMicrons` the per-channel scattering sigma in Film-Plane Microns.
    public struct Halation: Codable, Equatable, Sendable {
        public var strength: Double
        public var threshold: Double
        public var radiusMicrons: [Double]
        public var tint: [Double]
        public init(strength: Double, threshold: Double, radiusMicrons: [Double], tint: [Double]) {
            self.strength = strength; self.threshold = threshold; self.radiusMicrons = radiusMicrons; self.tint = tint
        }
    }
    public struct MTF: Codable, Equatable, Sendable {
        public var cyclesPerMM: [Double]
        public var response: [Double]
    }
    public struct Reciprocity: Codable, Equatable, Sendable {
        public var schwarzschildP: Double
        public var thresholdSeconds: Double
    }

    public func validate() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw FilmError.invalid("Profile \(id): \(message)") }
        }
        func nonnegative(_ values: [Double], count: Int) -> Bool {
            values.count == count && values.allSatisfy { $0.isFinite && $0 >= 0 }
        }
        try require(!id.isEmpty && !displayName.isEmpty, "missing identity or Display Name")
        try require([nominalISO, trueISO, balance].allSatisfy { $0.isFinite && $0 > 0 }, "invalid Stock speed or Stock Balance")
        try require((2...65).contains(colour.lutSize), "Colour Cube size must be 2...65")
        try require(process.isMonochrome == (monochrome != nil), "Monochrome section must occur only for B&W")
        try require(process.isMonochrome ? colour.lutVariants.isEmpty : !colour.lutVariants.isEmpty,
                    "B&W uses a Density Curve; colour uses Colour Cubes")
        try require(Set(colour.lutVariants.map(\.pushStops)).count == colour.lutVariants.count &&
                    colour.lutVariants.allSatisfy { $0.pushStops.isFinite && !$0.lut.isEmpty }, "invalid sparse Development Offsets")
        try require(process != .e6 || colour.outputStage == .none, "reversal has no Output Stage")
        if let monochrome {
            try require(nonnegative(monochrome.spectralWeight, count: 3) && monochrome.spectralWeight.reduce(0, +) > 0 &&
                        !monochrome.densityCurve.isEmpty, "invalid Monochrome Collapse")
        }
        try require(nonnegative([grain.rmsGranularity, grain.grainRadiusMicrons], count: 2) &&
                    nonnegative(grain.densityResponse, count: 32) && nonnegative(grain.channelRadiusScale, count: 3) &&
                    (0...1).contains(grain.channelCorrelation), "invalid Grain parameters")
        try require(nonnegative([halation.strength, halation.threshold], count: 2) && halation.strength <= 1 && halation.threshold > 0 &&
                    nonnegative(halation.radiusMicrons, count: 3) && halation.radiusMicrons.allSatisfy { $0 <= 5000 } &&
                    nonnegative(halation.tint, count: 3) && halation.tint.allSatisfy { $0 <= 1 }, "invalid Halation parameters")
        // Longer wavelengths scatter furthest through the base, so the red radius
        // leads. A Profile that inverts this is describing something else.
        try require(halation.radiusMicrons[0] >= halation.radiusMicrons[1] && halation.radiusMicrons[1] >= halation.radiusMicrons[2],
                    "Halation radii must not increase from red to blue")
        try require(derivedFrom.map { !$0.isEmpty && $0 != id } ?? true, "a Profile cannot be derived from itself")
        try require(!mtf.cyclesPerMM.isEmpty && nonnegative(mtf.cyclesPerMM, count: mtf.response.count) &&
                    nonnegative(mtf.response, count: mtf.cyclesPerMM.count) &&
                    zip(mtf.cyclesPerMM, mtf.cyclesPerMM.dropFirst()).allSatisfy { $0 < $1 }, "invalid MTF")
        try require(reciprocity.schwarzschildP.isFinite && reciprocity.schwarzschildP > 0 &&
                    reciprocity.thresholdSeconds.isFinite && reciprocity.thresholdSeconds >= 0, "invalid Reciprocity Failure")
        if let fingerprint = colour.sourceFingerprint {
            try require(colour.inputShaper != nil && fingerprint.count == 64 && fingerprint.allSatisfy { "0123456789abcdef".contains($0) },
                        "invalid spectral source fingerprint")
        }
        if let shaper = colour.inputShaper {
            try require([shaper.minimumLogExposure, shaper.maximumLogExposure, shaper.middleGrayLogExposure].allSatisfy { $0.isFinite && (-10...10).contains($0) } &&
                        shaper.minimumLogExposure < shaper.middleGrayLogExposure && shaper.middleGrayLogExposure < shaper.maximumLogExposure,
                        "invalid log-exposure shaper")
            try require(!process.isMonochrome && colour.cubeOutput == .displayLinearRec2020 && colour.outputStage == .scan,
                        "spectral Colour Cubes require the scan output contract")
        } else {
            try require(colour.cubeOutput != .displayLinearRec2020, "display-linear Colour Cube requires an input shaper")
        }
        var parameters = Self.parameterPaths
        if colour.inputShaper != nil { parameters += ["colour.inputShaper"] }
        if colour.cubeOutput != nil { parameters += ["colour.cubeOutput"] }
        if monochrome != nil { parameters += ["monochrome.spectralWeight", "monochrome.densityCurve"] }
        try require(parameters.allSatisfy { provenance[$0] != nil }, "missing per-parameter Provenance")
    }

    private static let parameterPaths = ["nominalISO", "trueISO", "balance", "format",
        "colour.lutVariants", "colour.lutSize", "colour.outputStage", "grain.model", "grain.rmsGranularity",
        "grain.grainRadiusMicrons", "grain.densityResponse", "grain.channelCorrelation", "grain.channelRadiusScale",
        "halation.strength", "halation.threshold", "halation.radiusMicrons", "halation.tint", "mtf.cyclesPerMM",
        "mtf.response", "reciprocity.schwarzschildP", "reciprocity.thresholdSeconds"]
}
