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

/// Where a parameter's value came from. `measured` is supported by a cited source
/// and `artistic` is a judgement made here. `approximation` is neither: the Stock
/// publishes no usable measurement of this parameter at all, and the value stands
/// in for one — a shape borrowed from a sibling Stock and adjusted, or a figure read
/// off reference scans. A Profile carrying one is not a claim about that film's
/// numbers, and the app says so rather than letting it pass as the other two.
public enum Provenance: String, Codable, Sendable { case measured, artistic, approximation }

/// How far a Profile's appearance has been checked against the Stock it models.
/// Distinct from `Provenance`, which records where one parameter's *value* came
/// from: a Profile can be built entirely from measured values and still never have
/// been compared with a photograph. Absent means `modelled`, so a Profile can never
/// claim more than it has by omitting the field.
public enum Accuracy: String, Codable, Sendable {
    /// Compared against held-out captures of the Stock and found to match. Nothing
    /// in the Catalogue is this yet; `Tests/…/FilmReferences/manifest.json` is empty.
    case validated
    /// Built from published data and judgement, with no photographic comparison made.
    case modelled
    /// Not a model of any Stock at all — the synthetic studies and the identity Profile.
    case synthetic
}

/// A Contrast Filter: coloured glass on the lens, modelled as a spectral multiply
/// applied before the Monochrome Collapse. Black & white only, and never a tint —
/// each case names a Profile's own Spectral Weight for light seen through that glass.
public enum ContrastFilter: String, Codable, Sendable, CaseIterable, Identifiable {
    case none, yellow, orange, red, green, blue
    public var id: String { rawValue }
    /// The glass, named by its colour and its depth. The transmittance model is
    /// digitised from a published filter series whose numbers are a live trademark,
    /// so the numbers stay in `Curves/contrast-filters/` and out of the interface.
    public var displayName: String {
        switch self {
        case .none: "No filter"
        case .yellow: "Yellow, light"
        case .orange: "Orange, deep"
        case .red: "Red, deep"
        case .green: "Green, medium"
        case .blue: "Blue, deep"
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
    /// How far this Profile has been checked against the Stock. Optional so that a
    /// Curve Set that omits it decodes, and so that omitting it is the modest claim.
    public var accuracy: Accuracy?

    /// Whether any parameter stands in for a measurement the Stock never published.
    /// The app says so wherever it names the Stock; see `Provenance.approximation`.
    public var isApproximation: Bool { provenance.values.contains(.approximation) }

    /// `accuracy` with its default applied. Never claims more than was authored.
    public var accuracyClaim: Accuracy { accuracy ?? .modelled }

    /// The word the app puts in front of a Display Name, or nil when the name stands
    /// unqualified. Approximation outranks accuracy because a borrowed measurement is
    /// the stronger caveat, and a study needs no qualifier — its own name says so.
    public var nameQualifier: String? {
        if isApproximation { return "Approx." }
        switch accuracyClaim {
        case .validated, .synthetic: return nil
        case .modelled: return "Modelled"
        }
    }

    /// The Display Name as the app must render it **wherever it names the Stock**.
    /// Every naming site reads this rather than `displayName`, so a redesign cannot
    /// silently drop the qualifier the way the editor rebuild did.
    /// `everyNamingSiteUsesTheQualifiedDisplayName` fails if a new site reaches for
    /// the bare name without saying, in the line, why it wants it.
    public var qualifiedDisplayName: String {
        guard let nameQualifier else { return displayName }
        return nameQualifier + " · " + displayName
    }

    /// The same claim spelled for VoiceOver, which reads a mid-dot as a pause and an
    /// abbreviation as letters.
    public var spokenDisplayName: String {
        guard nameQualifier != nil else { return displayName }
        return displayName + (isApproximation ? ", approximation" : ", modelled")
    }

    /// What an exported file is named after, before the extension.
    ///
    /// The Display Name rather than the id, and that is a trademark decision rather
    /// than a cosmetic one: ids still carry manufacturer marks — `portra-400`,
    /// `vision3-500t` — and they are internal handles only because nothing a user
    /// reads is derived from them. A filename is read. `Scripts/check-archive.py`
    /// asserts the same rule from the other end.
    ///
    /// The qualifier is deliberately absent: it belongs to the interface, where it
    /// can be explained, and "approx-linen-400.heif" in a share sheet explains
    /// nothing. `ExportedFile.fileName` sanitises whatever comes back, so an
    /// unusable name here is safe rather than merely unlikely.
    public var filenameStem: String {
        let name = displayName // bare-display-name: a filename, and a qualifier is interface
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined(separator: " ")
            .split(separator: " ").joined(separator: "-")
        return name.isEmpty ? id : name.lowercased()
    }

    public struct Colour: Codable, Equatable, Sendable {
        public var lutVariants: [Variant]
        /// One Colour Cube per Development Offset for the Print Output Stage, when
        /// the Stock has one: the same negative read by an enlarger and RA-4 paper
        /// instead of by a scanner. Nil is a Stock with no Print, which the renderer
        /// refuses rather than approximating with the scan. Like the scan cubes of a
        /// legacy spectral negative these are `displayLinearRec2020`. With
        /// `densityOutput`, both stages share film density payloads and the print
        /// observation lives in `densityOutput.printVariants`.
        public var printVariants: [Variant]?
        public var lutSize: Int
        public var outputStage: OutputStage
        /// Nil retains the foundation profiles' linear [0, 1] input and Density Space output.
        public var inputShaper: LogExposureShaper?
        public var cubeOutput: CubeOutput?
        /// SHA-256 of the offline model version and its authoring inputs; nil in stock.json.
        public var sourceFingerprint: String?
        /// Separate film density from its observation so Grain perturbs the film
        /// before scanning, printing or viewing. Absent on legacy fused cubes.
        public var densityOutput: DensityOutput?
    }
    public struct DensityOutput: Codable, Equatable, Sendable {
        public var minimum: [Double]
        public var maximum: [Double]
        public var lutSize: Int
        public var lutVariants: [Variant]
        public var printVariants: [Variant]?
        public init(minimum: [Double], maximum: [Double], lutSize: Int,
                    lutVariants: [Variant], printVariants: [Variant]?) {
            self.minimum = minimum; self.maximum = maximum; self.lutSize = lutSize
            self.lutVariants = lutVariants; self.printVariants = printVariants
        }
    }
    public enum CubeOutput: String, Codable, Sendable { case density, displayLinearRec2020 }
    /// Offline Colour Cube coordinates. Runtime application is the MEM-244 integration gate.
    public struct LogExposureShaper: Codable, Equatable, Sendable {
        public var minimumLogExposure: Double
        public var maximumLogExposure: Double
        /// Physical log10 lux-seconds corresponding to scene-linear 0.18.
        public var middleGrayLogExposure: Double
        public init(minimumLogExposure: Double, maximumLogExposure: Double, middleGrayLogExposure: Double) {
            self.minimumLogExposure = minimumLogExposure; self.maximumLogExposure = maximumLogExposure
            self.middleGrayLogExposure = middleGrayLogExposure
        }
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
        /// Per-band RGB coefficients before the shared nonnegative spectral
        /// projection. A dot product alone cannot reproduce clipping outside the
        /// reconstruction basis. Rows are normalized to preserve a neutral.
        public var spectralContributions: [SpectralContributions]?
        public struct SpectralContributions: Codable, Equatable, Sendable {
            public var filter: ContrastFilter
            public var coefficients: [[Double]]
            public init(filter: ContrastFilter, coefficients: [[Double]]) {
                self.filter = filter; self.coefficients = coefficients
            }
        }

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
        /// Absolute optical density and RMS density fluctuations at the 48 µm
        /// aperture, one curve per layer. Endpoint holding outside the measured
        /// domain is an explicitly recorded approximation.
        public var measuredDensityCurves: [[DensityGranularity]]?
        public struct DensityGranularity: Codable, Equatable, Sendable {
            public var density: Double
            public var rms: Double
            public init(density: Double, rms: Double) { self.density = density; self.rms = rms }
        }
        /// Whether the Stock grains at all. A Profile with no granularity, or a
        /// Density Response that is zero everywhere, has nothing for the Pass to add
        /// and no control to offer.
        public var isSilent: Bool {
            if let measuredDensityCurves { return !measuredDensityCurves.joined().contains { $0.rms > 0 } }
            return rmsGranularity <= 0 || !densityResponse.contains { $0 > 0 }
        }
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
        /// Published red/green/blue responses on the same frequency grid. Legacy
        /// profiles with a single measurement retain the shared response.
        public var channelResponse: [[Double]]?
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
        var names = Set(colour.lutVariants.map(\.lut))
        names.formUnion((colour.printVariants ?? []).map(\.lut))
        names.formUnion((colour.densityOutput?.lutVariants ?? []).map(\.lut))
        names.formUnion((colour.densityOutput?.printVariants ?? []).map(\.lut))
        if let monochrome { names.insert(monochrome.densityCurve) }
        return names
    }

    /// The longest a Profile id may be, which is also how far the Export truncates a
    /// filename built from one.
    static let maximumIDLength = 64

    /// What a Profile id may contain. The Export's filename sanitiser reads the same
    /// rule, so the validator and the sanitiser cannot drift apart.
    static func isSlugCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
    }

    public func validate() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw FilmError.invalid("Profile \(id): \(message)") }
        }
        func nonnegative(_ values: [Double], count: Int) -> Bool {
            values.count == count && values.allSatisfy { $0.isFinite && $0 >= 0 }
        }
        try require(!id.isEmpty && !displayName.isEmpty, "missing identity or Display Name")
        // The id becomes a filename component on Export, and `appendingPathComponent`
        // accepts `../` without complaint. Constraining it here rather than at the
        // exporter is what keeps filename safety from resting on the Catalogue's
        // contents staying well-behaved.
        try require(id.count <= Self.maximumIDLength && id.allSatisfy(Self.isSlugCharacter),
                    "Profile id must be a short ASCII slug")
        try require([nominalISO, trueISO, balance].allSatisfy { $0.isFinite && $0 > 0 }, "invalid Stock speed or Stock Balance")
        try require((2...129).contains(colour.lutSize), "Colour Cube size must be 2...129")
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
            try require(colour.densityOutput != nil || Set(printVariants.map(\.lut)).isDisjoint(with: Set(colour.lutVariants.map(\.lut))),
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
            if let spectra = monochrome.spectralContributions {
                try require(Set(spectra.map(\.filter)) == Set(ContrastFilter.allCases) && spectra.count == 6 &&
                            spectra.allSatisfy { entry in
                                (31...81).contains(entry.coefficients.count) && entry.coefficients.allSatisfy {
                                    $0.count == 3 && $0.allSatisfy(\.isFinite)
                                } && abs(entry.coefficients.flatMap { $0 }.reduce(0, +) - 1) < 1e-6
                            }, "invalid nonnegative spectral reconstruction coefficients")
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
        if let measured = grain.measuredDensityCurves {
            try require(measured.count == 3 && measured.allSatisfy { curve in
                curve.count >= 2 && curve.allSatisfy { $0.density.isFinite && $0.density >= 0 && $0.rms.isFinite && $0.rms >= 0 }
                    && zip(curve, curve.dropFirst()).allSatisfy { $0.density < $1.density }
            }, "invalid measured density/granularity curves")
            try require(colour.cubeOutput != .displayLinearRec2020, "measured grain requires a Density Space response")
        }
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
        if let channels = mtf.channelResponse {
            try require(channels.count == 3 && channels.allSatisfy { nonnegative($0, count: mtf.cyclesPerMM.count) },
                        "invalid channel MTF curves")
        }
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
            try require(process.isMonochrome ? colour.cubeOutput == nil :
                            (colour.densityOutput == nil ? colour.cubeOutput == .displayLinearRec2020 : colour.cubeOutput == .density),
                        "spectral Colour Cubes require the scan output contract; a Density Curve has no cube output")
        } else {
            try require(colour.cubeOutput != .displayLinearRec2020, "display-linear Colour Cube requires an input shaper")
        }
        if let output = colour.densityOutput {
            try require(colour.inputShaper != nil && !process.isMonochrome && colour.cubeOutput == .density,
                        "density output requires a shaped colour density cube")
            try require(output.minimum.count == 3 && output.maximum.count == 3 &&
                        zip(output.minimum, output.maximum).allSatisfy { $0.isFinite && $1.isFinite && $0 < $1 } &&
                        (2...65).contains(output.lutSize), "invalid output density domain")
            func matches(_ outputs: [Variant], _ inputs: [Variant]) -> Bool {
                outputs.count == inputs.count && Set(outputs.map(\.pushStops)) == Set(inputs.map(\.pushStops))
                    && outputs.allSatisfy { !$0.lut.isEmpty }
            }
            try require(matches(output.lutVariants, colour.lutVariants) &&
                        (output.printVariants == nil) == (colour.printVariants == nil) &&
                        matches(output.printVariants ?? [], colour.printVariants ?? []), "density output variants must match film variants")
            let filmNames = Set((colour.lutVariants + (colour.printVariants ?? [])).map(\.lut))
            let outputNames = Set((output.lutVariants + (output.printVariants ?? [])).map(\.lut))
            try require(filmNames.isDisjoint(with: outputNames), "density/output payload names must be distinct")
        }
        var parameters = Self.parameterPaths
        if colour.inputShaper != nil { parameters += ["colour.inputShaper"] }
        if colour.cubeOutput != nil { parameters += ["colour.cubeOutput"] }
        if colour.printVariants != nil { parameters += ["colour.printVariants"] }
        if colour.densityOutput != nil { parameters += ["colour.densityOutput"] }
        if grain.measuredDensityCurves != nil { parameters += ["grain.measuredDensityCurves", "grain.densityExtrapolation"] }
        if mtf.channelResponse != nil { parameters += ["mtf.channelResponse"] }
        if monochrome != nil {
            parameters += ["monochrome.spectralWeight", "monochrome.densityCurve"]
            if colour.inputShaper != nil { parameters += ["monochrome.contrastFilters"] }
            if monochrome?.spectralContributions != nil { parameters += ["monochrome.spectralContributions"] }
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
