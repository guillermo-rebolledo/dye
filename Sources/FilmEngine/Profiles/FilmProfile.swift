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

/// A Contrast Filter: coloured glass on the lens, modelled as a spectral multiply
/// applied before the Monochrome Collapse. Black & white only, and never a tint —
/// each case names a Profile's own Spectral Weight for light seen through that glass.
public enum ContrastFilter: String, Codable, Sendable, CaseIterable, Identifiable {
    case none, yellow, orange, red, green, blue
    public var id: String { rawValue }
    /// The glass, named by the Wratten number the transmittance model describes.
    public var displayName: String {
        switch self {
        case .none: "No filter"
        case .yellow: "Yellow (Wratten 8)"
        case .orange: "Orange (Wratten 15)"
        case .red: "Red (Wratten 25)"
        case .green: "Green (Wratten 58)"
        case .blue: "Blue (Wratten 47)"
        }
    }
    /// What the glass is for, in the terms a photographer chooses it in.
    public var effect: String {
        switch self {
        case .none: "The stock's own rendering of colour."
        case .yellow: "Darkens blue sky a little and separates cloud from it. The everyday filter."
        case .orange: "Darkens sky further and cuts haze; skin and brick lighten."
        case .red: "Sky goes nearly black, foliage darkens, and haze all but disappears."
        case .green: "Lightens foliage and darkens sky and skin; the landscape filter for greens."
        case .blue: "Lightens sky and haze and darkens everything warm. Rarely wanted, and deliberately so."
        }
    }
}
/// What happens to a negative after the film. Reversal Stocks use `none`, because
/// the film is already the final image.
public enum OutputStage: String, Codable, Sendable, CaseIterable {
    case scan, print, none
    /// How the choice reads in the editor. `none` never appears in a picker — it is
    /// the absence of a choice rather than a third option — but it names itself for
    /// the card that explains why there is nothing to choose.
    public var displayName: String {
        switch self {
        case .scan: "Scan"
        case .print: "Print"
        case .none: "The film itself"
        }
    }
}
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
    public var bloom: Bloom
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
        /// One Colour Cube per Development Offset for the Print Output Stage, when
        /// the Stock has one: the same negative read by an enlarger and RA-4 paper
        /// instead of by a scanner. Nil is a Stock with no Print, which the renderer
        /// refuses rather than approximating with the scan. Like the scan cubes of a
        /// spectral negative these are `displayLinearRec2020`, because the print is
        /// the final image the way a Transparency is.
        public var printVariants: [Variant]?
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
    /// The black & white branch. `spectralWeight` collapses linear RGB to one grey
    /// channel and `densityCurve` names the 1024-entry Density Curve that grey reads.
    /// Both it and `contrastFilters` are derived by the Baker from a Stock's measured
    /// spectral sensitivity, so like `colour.sourceFingerprint` they are absent from
    /// authoring metadata and required in a baked Profile.
    public struct Monochrome: Codable, Equatable, Sendable {
        public var spectralWeight: [Double]?
        public var densityCurve: String
        /// One Spectral Weight per Contrast Filter, in the Stock's own sensitivity
        /// units, so the ratio of their sums is the glass's filter factor.
        public var contrastFilters: [FilterWeight]?

        public struct FilterWeight: Codable, Equatable, Sendable {
            public var filter: ContrastFilter
            public var spectralWeight: [Double]
            public init(filter: ContrastFilter, spectralWeight: [Double]) {
                self.filter = filter; self.spectralWeight = spectralWeight
            }
        }

        public init(spectralWeight: [Double]? = nil, densityCurve: String, contrastFilters: [FilterWeight]? = nil) {
            self.spectralWeight = spectralWeight; self.densityCurve = densityCurve; self.contrastFilters = contrastFilters
        }

        /// The Spectral Weight this Stock collapses with through `filter`, normalised
        /// so a neutral keeps its exposure. Normalising *is* the filter factor: a
        /// photographer meters without the glass and opens up by what it costs, so
        /// what the Contrast Filter changes is tonal separation and not brightness.
        /// Nil when the Profile carries no weight for that glass.
        public func weight(for filter: ContrastFilter) -> [Double]? {
            let raw = filter == .none ? spectralWeight : contrastFilters?.first { $0.filter == filter }?.spectralWeight
            guard let raw, case let total = raw.reduce(0, +), total > 0 else { return nil }
            return raw.map { $0 / total }
        }

        /// What `filter` costs in stops, relative to this Stock unfiltered. Positive:
        /// every Contrast Filter subtracts light. Nil when either weight is missing.
        public func filterFactorStops(_ filter: ContrastFilter) -> Double? {
            guard let base = spectralWeight?.reduce(0, +), base > 0,
                  let filtered = (filter == .none ? spectralWeight : contrastFilters?.first { $0.filter == filter }?.spectralWeight)?.reduce(0, +),
                  filtered > 0 else { return nil }
            return log2(base / filtered)
        }
    }
    public struct Grain: Codable, Equatable, Sendable {
        public var model: GrainModel
        public var rmsGranularity: Double
        public var grainRadiusMicrons: Double
        public var densityResponse: [Double]
        public var channelCorrelation: Double
        public var channelRadiusScale: [Double]
        /// Whether the Stock grains at all. A Profile with no granularity, or a
        /// Density Response that is zero everywhere, has nothing for the Pass to add
        /// and no control to offer.
        public var isSilent: Bool { rmsGranularity <= 0 || !densityResponse.contains { $0 > 0 } }
        public init(model: GrainModel, rmsGranularity: Double, grainRadiusMicrons: Double,
                    densityResponse: [Double], channelCorrelation: Double, channelRadiusScale: [Double]) {
            self.model = model; self.rmsGranularity = rmsGranularity; self.grainRadiusMicrons = grainRadiusMicrons
            self.densityResponse = densityResponse; self.channelCorrelation = channelCorrelation
            self.channelRadiusScale = channelRadiusScale
        }
    }
    /// Lens diffusion: `strength` is the fraction of all light the taking lens spreads
    /// across the frame, and `radiusMicrons` the sigma it spreads it over in Film-Plane
    /// Microns. A property of the lens rather than of the Stock, carried per Profile so
    /// the user's control has a physically motivated default to scale, and therefore
    /// always `artistic`.
    public struct Bloom: Codable, Equatable, Sendable {
        public var strength: Double
        public var radiusMicrons: Double
        public init(strength: Double, radiusMicrons: Double) {
            self.strength = strength; self.radiusMicrons = radiusMicrons
        }
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
        public init(cyclesPerMM: [Double], response: [Double]) {
            self.cyclesPerMM = cyclesPerMM; self.response = response
        }
    }
    /// Loss of sensitivity at long exposure times. Below `thresholdSeconds` a Stock
    /// obeys reciprocity exactly; above it, each layer keeps its own Schwarzschild
    /// exponent, because the three lose speed at different rates and that is what
    /// makes the published compensation a colour-correction filter and not just an
    /// extra stop.
    public struct Reciprocity: Codable, Equatable, Sendable {
        public var schwarzschildP: [Double]
        public var thresholdSeconds: Double

        /// Whether the Stock fails at all. A Curve Set that records no failure has
        /// nothing for an exposure time to change, and no control to offer.
        public var isSilent: Bool { thresholdSeconds <= 0 || schwarzschildP.allSatisfy { $0 >= 1 } }

        /// The per-channel scale on scene-linear light for an exposure of `seconds`.
        /// One everywhere below the threshold, and one in every channel whose
        /// exponent is 1 — a Stock the Curve Set records no failure for.
        public func gain(seconds: Double) -> [Double] {
            guard seconds > thresholdSeconds, !isSilent else { return [1, 1, 1] }
            return schwarzschildP.map { pow(seconds / thresholdSeconds, $0 - 1) }
        }
    }

    /// Every payload this Profile's container has to carry: a Colour Cube per
    /// Development Offset for each Output Stage it can reach, or the one Density
    /// Curve of a black & white Stock.
    public var payloadNames: Set<String> {
        Set(colour.lutVariants.map(\.lut) + (colour.printVariants ?? []).map(\.lut)
            + (monochrome.map { [$0.densityCurve] } ?? []))
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
        if let printVariants = colour.printVariants {
            // The Print reads the same negative the scan does, so it is offered for
            // exactly the Development Offsets the scan is, and only where there is a
            // negative and a spectral model to read it with.
            try require(colour.outputStage == .scan && colour.inputShaper != nil && !process.isMonochrome,
                        "a Print Output Stage needs a spectral negative")
            try require(Set(printVariants.map(\.pushStops)) == Set(colour.lutVariants.map(\.pushStops)) &&
                        printVariants.count == colour.lutVariants.count &&
                        printVariants.allSatisfy { !$0.lut.isEmpty },
                        "Print Colour Cubes must cover the same Development Offsets as the scan's")
            try require(Set(printVariants.map(\.lut)).isDisjoint(with: Set(colour.lutVariants.map(\.lut))),
                        "Print Colour Cubes need payloads of their own")
        }
        if let monochrome {
            try require(!monochrome.densityCurve.isEmpty, "invalid Monochrome Collapse")
            if let weight = monochrome.spectralWeight {
                try require(nonnegative(weight, count: 3) && weight.reduce(0, +) > 0, "invalid Spectral Weight")
            }
            if let filters = monochrome.contrastFilters {
                // A Contrast Filter's weight may carry a small negative component: it is
                // the film's response to filtered light resolved onto the Working Space
                // primaries, and glass that blocks one primary can push it below zero.
                // Only the collapse of a neutral has to stay positive.
                try require(Set(filters.map(\.filter)) == Set(ContrastFilter.allCases).subtracting([ContrastFilter.none]) &&
                            filters.count == 5 && filters.allSatisfy { entry in
                                entry.spectralWeight.count == 3 && entry.spectralWeight.allSatisfy(\.isFinite) &&
                                entry.spectralWeight.reduce(0, +) > 0
                            }, "invalid Contrast Filter Spectral Weights")
                try require(colour.inputShaper != nil, "Contrast Filters are derived from a spectral Curve Set")
            }
            // Derived by the Baker, exactly like the source fingerprint: absent while
            // authoring, and both present in anything that ships.
            try require(colour.sourceFingerprint == nil ||
                        (monochrome.spectralWeight != nil && monochrome.contrastFilters != nil),
                        "a baked B&W Profile carries a derived Spectral Weight and Contrast Filters")
            try require(colour.inputShaper != nil || (monochrome.spectralWeight != nil && monochrome.contrastFilters == nil),
                        "a foundation study Profile authors its Spectral Weight and has no Contrast Filters")
        }
        try require(nonnegative([grain.rmsGranularity, grain.grainRadiusMicrons], count: 2) &&
                    nonnegative(grain.densityResponse, count: 32) && nonnegative(grain.channelRadiusScale, count: 3) &&
                    (0...1).contains(grain.channelCorrelation), "invalid Grain parameters")
        try require(nonnegative([bloom.strength, bloom.radiusMicrons], count: 2) && bloom.strength <= 1 &&
                    bloom.radiusMicrons <= 5000, "invalid Bloom parameters")
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
        try require(nonnegative(reciprocity.schwarzschildP, count: 3) &&
                    reciprocity.schwarzschildP.allSatisfy { $0 > 0 && $0 <= 1 } &&
                    reciprocity.thresholdSeconds.isFinite && reciprocity.thresholdSeconds >= 0, "invalid Reciprocity Failure")
        if let fingerprint = colour.sourceFingerprint {
            try require(colour.inputShaper != nil && fingerprint.count == 64 && fingerprint.allSatisfy { "0123456789abcdef".contains($0) },
                        "invalid spectral source fingerprint")
        }
        if let shaper = colour.inputShaper {
            try require([shaper.minimumLogExposure, shaper.maximumLogExposure, shaper.middleGrayLogExposure].allSatisfy { $0.isFinite && (-10...10).contains($0) } &&
                        shaper.minimumLogExposure < shaper.middleGrayLogExposure && shaper.middleGrayLogExposure < shaper.maximumLogExposure,
                        "invalid log-exposure shaper")
            // A negative's spectral cube carries the Baker's scan; a reversal cube
            // carries the transparency itself, which is why it has no Output Stage.
            // A B&W Profile has no cube at all, so it has no cube output to describe,
            // and its Density Curve is scanned by the runtime like any negative's.
            try require(colour.outputStage == (process == .e6 ? OutputStage.none : .scan),
                        "spectral Colour Cubes require the scan or the reversal output contract")
            try require(process.isMonochrome ? colour.cubeOutput == nil : colour.cubeOutput == .displayLinearRec2020,
                        "spectral Colour Cubes require the scan output contract; a Density Curve has no cube output")
        } else {
            try require(colour.cubeOutput != .displayLinearRec2020, "display-linear Colour Cube requires an input shaper")
        }
        var parameters = Self.parameterPaths
        if colour.inputShaper != nil { parameters += ["colour.inputShaper"] }
        if colour.cubeOutput != nil { parameters += ["colour.cubeOutput"] }
        if colour.printVariants != nil { parameters += ["colour.printVariants"] }
        if monochrome != nil {
            parameters += ["monochrome.spectralWeight", "monochrome.densityCurve"]
            if colour.inputShaper != nil { parameters += ["monochrome.contrastFilters"] }
        }
        try require(parameters.allSatisfy { provenance[$0] != nil }, "missing per-parameter Provenance")
    }

    private static let parameterPaths = ["nominalISO", "trueISO", "balance", "format",
        "colour.lutVariants", "colour.lutSize", "colour.outputStage", "grain.model", "grain.rmsGranularity",
        "grain.grainRadiusMicrons", "grain.densityResponse", "grain.channelCorrelation", "grain.channelRadiusScale",
        "bloom.strength", "bloom.radiusMicrons",
        "halation.strength", "halation.threshold", "halation.radiusMicrons", "halation.tint", "mtf.cyclesPerMM",
        "mtf.response", "reciprocity.schwarzschildP", "reciprocity.thresholdSeconds"]
}
