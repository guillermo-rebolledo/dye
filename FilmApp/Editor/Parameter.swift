import SwiftUI
import FilmEngine

/// One of the deck's three stages, in the order light travels: what happened to
/// the light before the film, the Film Response itself, and what happens to the
/// negative afterwards.
///
/// This is the stage *selector's* stage and has nothing to do with the Output
/// Stage, which is one of the parameters the Lab stage offers. `CONTEXT.md` warns
/// that bare "stage" collides, so the type is qualified rather than the term.
enum EditorStage: String, CaseIterable, Identifiable, Hashable {
    case light, film, lab

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light: "Light"
        case .film: "Film"
        case .lab: "Lab"
        }
    }
}

/// Ranges the editor imposes on top of the engine's own.
///
/// Both of these are deliberately narrower than what `RenderSettings` accepts,
/// because the engine's range is what a Preset may hold and this is what a 393 pt
/// track can usefully resolve. **A value outside one of these is valid.** It
/// arrives from a Preset, it renders, and it is never rejected or written back:
/// the indicator parks at the wall and the readout tells the truth.
enum EditorRange {
    /// A UI clamp inside `RenderSettings.exposureRange`, which is ±6 EV. Six stops
    /// across the track is 1/50 EV per point and unusable.
    static let exposure = -3.0...3.0

    /// A UI clamp inside `RenderSettings.temperatureRange`, which is 1667…25000 K.
    static let temperature = 2000.0...10000.0

    /// The exposure-time dial is spaced in stops of `log2(seconds)`, because that
    /// is how a shutter speed dial is spaced, over the engine's own seconds range.
    static let exposureTimeStops =
        log2(RenderSettings.exposureSecondsRange.lowerBound)...log2(RenderSettings.exposureSecondsRange.upperBound)
}

/// One control the deck can offer, as a value rather than as a call site.
///
/// Everything the old scrolling editor kept inline — the range, the step, the
/// format string, the conditional that decided whether the control appeared at
/// all, and the caption computed beside it — lives here. The deck enumerates the
/// parameters a stage offers and asks each one for its chip label, its readout,
/// its detent and its caption; nothing else in the app needs to know the rules.
///
/// A parameter a Stock does not have is **absent from the array**, never present
/// and disabled. A Stock with no reciprocity failure has nothing for an exposure
/// time control to change, and offering an inert one would say it did.
struct Parameter: Identifiable {
    /// What a parameter is, independent of the Stock on screen. This is what
    /// `EditorSelection` remembers and what a chip is keyed by.
    enum Identity: String, CaseIterable, Hashable {
        case exposure, temperature, tint, exposureTime
        case contrastFilter, development, bloom, halation, grain
        case outputStage, vignette, gateWeave, frameBorder
    }

    /// Which control draws the parameter. Not everything is a scrubber, and the
    /// active-control area keeps its height while changing what fills the track.
    enum Control {
        case scrubber
        case shutterDial
        case contrastFilterDiscs
        case outputStageCards
    }

    /// The tag on the right of the active control's header.
    enum Tag {
        /// The value is sitting on the parameter's detent.
        case detent
        /// The value is zero on a parameter whose zero means the effect is not
        /// applied at all. Off must look off, so it is called out rather than
        /// left to read as one number among the rest.
        case off
    }

    let id: Identity
    let name: String
    let stage: EditorStage
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double
    /// The value the control sticks to on the way past: the Stock's own value, or
    /// the neutral one. Nil for a parameter with no such value.
    let detent: Double?
    let control: Control
    let format: (Double) -> String
    /// Read on every draw rather than stored, because several captions change as
    /// the value crosses the Stock Balance or the reciprocity threshold.
    let caption: (() -> String)?
    /// Whether zero on this parameter means "not applied" rather than "the least
    /// of it". True for the geometry three and nothing else.
    let readsOffAtZero: Bool

    init(id: Identity, name: String, stage: EditorStage, value: Binding<Double>,
         range: ClosedRange<Double>, step: Double, detent: Double? = nil,
         control: Control = .scrubber, format: @escaping (Double) -> String,
         caption: (() -> String)? = nil, readsOffAtZero: Bool = false) {
        self.id = id
        self.name = name
        self.stage = stage
        self.value = value
        self.range = range
        self.step = step
        self.detent = detent
        self.control = control
        self.format = format
        self.caption = caption
        self.readsOffAtZero = readsOffAtZero
    }

    /// The value as the readout and the chip say it.
    var readout: String { format(value.wrappedValue) }

    /// The caption under the control, or nil when the parameter has nothing to say.
    var captionText: String? { caption?() }

    var tag: Tag? { tag(at: value.wrappedValue) }

    func tag(at value: Double) -> Tag? {
        if readsOffAtZero, value == 0 { return .off }
        if isAtDetent(value) { return .detent }
        return nil
    }

    /// Within half a step counts as on the detent: the control cannot be left
    /// between two steps, and an exact comparison would miss a detent that does
    /// not fall on a step boundary, as the Stock Balance in Kelvin need not.
    func isAtDetent(_ value: Double) -> Bool {
        guard let detent else { return false }
        return abs(value - detent) < step / 2
    }

    /// Where the indicator sits on the track, 0 at the lower wall and 1 at the
    /// upper. A value outside the editor's clamp parks at the wall rather than
    /// running off the end, and the readout still reports the real value.
    func fraction(of value: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    var fraction: Double { fraction(of: value.wrappedValue) }

    /// Where the anchor is drawn, or nil when the parameter has no detent.
    var detentFraction: Double? { detent.map(fraction(of:)) }

    /// A shutter speed as a photographer reads one. Shared by the exposure-time
    /// format and by `reciprocityHint`, which names the threshold the same way.
    static func shutterSpeed(_ seconds: Double) -> String {
        if seconds >= 1 { return seconds < 60 ? String(format: "%.0f s", seconds) : String(format: "%.0f min", seconds / 60) }
        return String(format: "1/%.0f s", 1 / seconds)
    }
}

// The reset is the setting's default, not its detent: tungsten Stock Balance
// is 3200 K, while a fresh editor's Scene Illuminant is still 5500 K.
extension Parameter {
    var defaultValue: Double {
        let defaults = RenderSettings()
        switch id {
        case .exposure: return defaults.exposureStops
        case .temperature: return defaults.temperatureKelvin
        case .tint: return defaults.tint
        case .exposureTime: return log2(defaults.exposureSeconds)
        case .development: return min(max(defaults.developmentOffset, range.lowerBound), range.upperBound)
        case .bloom: return defaults.bloomIntensity
        case .halation: return defaults.halationIntensity
        case .grain: return defaults.grainIntensity
        case .vignette: return defaults.vignette
        case .gateWeave: return defaults.gateWeave
        case .frameBorder: return defaults.frameBorder
        case .contrastFilter, .outputStage: return 0
        }
    }

    /// Presentation runs belong with the formatter, so views never need to
    /// know how a parameter spells its unit. The combined legacy readout stays
    /// unchanged for chips and accessibility.
    var readoutParts: (number: String, unit: String) {
        let text = readout
        if id == .contrastFilter, let split = text.range(of: "  ") {
            return (String(text[..<split.lowerBound]), String(text[split.upperBound...]))
        }
        if text.hasSuffix("%") { return (String(text.dropLast()), "%") }
        if let space = text.lastIndex(of: " "), text.first?.isNumber == true || text.first == "+" || text.first == "-" {
            return (String(text[..<space]), String(text[text.index(after: space)...]))
        }
        return (text, "")
    }

    /// Reserve the widest value before a drag begins, including word-valued
    /// defaults such as “neutral”. Discrete controls include every option.
    var readoutWidthReference: String {
        var values = [range.lowerBound, range.upperBound, defaultValue]
        if let detent { values.append(detent) }
        if control == .contrastFilterDiscs || control == .outputStageCards {
            values += stride(from: range.lowerBound, through: range.upperBound, by: step).map { $0 }
        }
        return values.map(format).max { $0.count < $1.count } ?? readout
    }

    var isModified: Bool { abs(value.wrappedValue - defaultValue) > 0.000001 }
}

// MARK: - The parameters a Stock offers

extension EditorModel {
    /// The parameters this Stock offers at the given stage, in the order they are
    /// shown. Rebuilt on every read rather than cached, because a change of Stock
    /// changes the list — `stockChanged()` clamps the Development Offset and
    /// resets the Contrast Filter and Output Stage, and a deck holding on to a
    /// stale list would keep showing a control the new Stock does not have.
    func parameters(for stage: EditorStage) -> [Parameter] {
        switch stage {
        case .light: lightParameters
        case .film: filmParameters
        case .lab: labParameters
        }
    }

    /// Every parameter on offer, across all three stages.
    var allParameters: [Parameter] { EditorStage.allCases.flatMap(parameters(for:)) }

    private var lightParameters: [Parameter] {
        var parameters = [
            Parameter(id: .exposure, name: "Exposure", stage: .light,
                      value: binding(\.settings.exposureStops),
                      range: EditorRange.exposure, step: 1 / 6, detent: 0,
                      format: { String(format: "%+.1f EV", $0) }),
            Parameter(id: .temperature, name: "Temperature", stage: .light,
                      value: binding(\.settings.temperatureKelvin),
                      range: EditorRange.temperature, step: 50,
                      // The detent is the Stock Balance, not a fixed 5500 K: it is
                      // the temperature this Stock records as neutral.
                      detent: profile.metadata.balance,
                      format: { String(format: "%.0f K", $0) },
                      caption: { [weak self] in self?.balanceHint ?? "" }),
            Parameter(id: .tint, name: "Tint", stage: .light,
                      value: binding(\.settings.tint),
                      range: RenderSettings.tintRange, step: 1, detent: 0,
                      format: { $0 == 0 ? "neutral" : String(format: "%+.0f %@", $0, $0 > 0 ? "magenta" : "green") }),
        ]
        if hasReciprocity {
            // Shutter speeds are a stop apart, so the control moves in stops and
            // the label says the time. A stock that obeys reciprocity throughout
            // has no such control at all rather than a control that does nothing.
            parameters.append(
                Parameter(id: .exposureTime, name: "Exposure time", stage: .light,
                          value: exposureStopsBinding,
                          range: EditorRange.exposureTimeStops, step: 1 / 3,
                          detent: log2(reciprocityThresholdSeconds),
                          control: .shutterDial,
                          format: { Parameter.shutterSpeed(pow(2, $0)) },
                          caption: { [weak self] in self?.reciprocityHint ?? "" }))
        }
        return parameters
    }

    private var filmParameters: [Parameter] {
        var parameters: [Parameter] = []
        if !contrastFilters.isEmpty {
            let filters = contrastFilters
            parameters.append(
                Parameter(id: .contrastFilter, name: "Contrast filter", stage: .film,
                          value: contrastFilterBinding,
                          range: 0...Double(filters.count - 1), step: 1,
                          control: .contrastFilterDiscs,
                          format: { [weak self] index in
                              let filter = filters[Self.index(index, in: filters)]
                              // The published factor for *that* glass, not for the
                              // one fitted, so a disc reads the same whether or not
                              // it is the selected one. Unsigned, because a filter
                              // factor is a cost and only points one way — and the
                              // render has already added the stops back, so a minus
                              // sign would say the picture got darker when nothing did.
                              guard filter != .none,
                                    let stops = self?.profile.metadata.monochrome?.filterFactorStops(filter)
                              else { return filter.displayName }
                              return String(format: "%@  %.1f stop", filter.displayName, abs(stops))
                          },
                          caption: { [weak self] in self?.contrastFilterHint ?? "" }))
        }
        if let range = developmentRange {
            parameters.append(
                Parameter(id: .development, name: "Development", stage: .film,
                          value: binding(\.settings.developmentOffset),
                          range: range, step: 0.1, detent: 0,
                          format: Self.developmentLabel,
                          caption: { [weak self] in self?.developmentHint ?? "" }))
        }
        // 100 % is the Stock's own modelled value on all three, which is why the
        // detent sits there rather than at zero: above it the user is knowingly
        // exaggerating, and the detent is what tells them where that line is.
        if hasBloom {
            parameters.append(
                Parameter(id: .bloom, name: "Bloom", stage: .film,
                          value: binding(\.settings.bloomIntensity),
                          range: RenderSettings.bloomRange, step: 0.05, detent: 1,
                          format: Self.percentage,
                          caption: { [weak self] in self?.bloomHint ?? "" }))
        }
        if hasHalation {
            parameters.append(
                Parameter(id: .halation, name: "Halation", stage: .film,
                          value: binding(\.settings.halationIntensity),
                          range: RenderSettings.halationRange, step: 0.05, detent: 1,
                          format: Self.percentage,
                          caption: { [weak self] in self?.halationHint ?? "" }))
        }
        if hasGrain {
            parameters.append(
                Parameter(id: .grain, name: "Grain", stage: .film,
                          value: binding(\.settings.grainIntensity),
                          range: RenderSettings.grainRange, step: 0.05, detent: 1,
                          format: Self.percentage,
                          caption: { [weak self] in self?.grainHint ?? "" }))
        }
        return parameters
    }

    private var labParameters: [Parameter] {
        var parameters: [Parameter] = []
        // A negative is scanned or printed, and the two are different pictures
        // rather than different settings, so the choice leads the stage instead of
        // sitting under the controls that only trim it. A choice of one is not a
        // choice, so a Stock with nothing to choose is not offered the control.
        if !outputStages.isEmpty {
            let stages = outputStages
            parameters.append(
                Parameter(id: .outputStage, name: "Read the negative by", stage: .lab,
                          value: outputStageBinding,
                          range: 0...Double(stages.count - 1), step: 1,
                          control: .outputStageCards,
                          format: { stages[Self.index($0, in: stages)].displayName },
                          caption: { [weak self] in self?.outputDescription ?? "" }))
        }
        // None of the three is a property of the Stock, so all three start at zero
        // and zero means the effect is not applied rather than the least of it.
        parameters.append(contentsOf: [
            Parameter(id: .vignette, name: "Vignette", stage: .lab,
                      value: binding(\.settings.vignette),
                      range: RenderSettings.vignetteRange, step: 0.05, detent: 0,
                      format: { $0 == 0 ? "none" : Self.percentage($0) }, readsOffAtZero: true),
            Parameter(id: .gateWeave, name: "Gate weave", stage: .lab,
                      value: binding(\.settings.gateWeave),
                      range: RenderSettings.gateWeaveRange, step: 0.05, detent: 0,
                      format: { $0 == 0 ? "steady" : Self.percentage($0) }, readsOffAtZero: true),
            Parameter(id: .frameBorder, name: "Frame border", stage: .lab,
                      value: binding(\.settings.frameBorder),
                      range: RenderSettings.frameBorderRange, step: 0.05, detent: 0,
                      format: { $0 == 0 ? "none" : Self.percentage($0) }, readsOffAtZero: true),
        ])
        return parameters
    }

    // MARK: - Bindings

    private func binding(_ keyPath: ReferenceWritableKeyPath<EditorModel, Double>) -> Binding<Double> {
        Binding(get: { self[keyPath: keyPath] }, set: { self[keyPath: keyPath] = $0 })
    }

    /// The exposure time in stops, which is how a shutter speed dial is spaced.
    var exposureStopsBinding: Binding<Double> {
        Binding(get: { log2(self.settings.exposureSeconds) },
                set: { self.settings.exposureSeconds = min(max(pow(2, $0), RenderSettings.exposureSecondsRange.lowerBound),
                                                           RenderSettings.exposureSecondsRange.upperBound) })
    }

    /// A discrete choice as a position in the list it is chosen from, so the deck
    /// can enumerate every parameter as one type and the discs and the cards only
    /// have to know how many positions there are.
    private var contrastFilterBinding: Binding<Double> {
        let filters = contrastFilters
        return Binding(get: { Double(filters.firstIndex(of: self.settings.contrastFilter) ?? 0) },
                       set: { self.settings.contrastFilter = filters[Self.index($0, in: filters)] })
    }

    private var outputStageBinding: Binding<Double> {
        let stages = outputStages
        return Binding(get: { Double(stages.firstIndex(of: self.outputStage) ?? 0) },
                       set: { self.outputStage = stages[Self.index($0, in: stages)] })
    }

    private static func index<Element>(_ value: Double, in list: [Element]) -> Int {
        min(max(Int(value.rounded()), 0), list.count - 1)
    }

    // MARK: - Formats

    private static func percentage(_ value: Double) -> String { String(format: "%.0f%%", value * 100) }

    private static func developmentLabel(_ offset: Double) -> String {
        if abs(offset) < 0.05 { return "normal" }
        return String(format: "%@ %+.1f", offset > 0 ? "push" : "pull", offset)
    }
}

// MARK: - Captions

/// The copy under each control. Every one of these is verbatim from the editor it
/// was lifted out of; several are live and change as the value crosses the Stock
/// Balance or the reciprocity threshold, which is why they are read on each draw.
extension EditorModel {
    var balanceHint: String {
        let balance = profile.metadata.balance
        let difference = settings.temperatureKelvin - balance
        if difference == 0 { return "Scene light matches the stock's \(Int(balance)) K balance: neutral on film." }
        let direction = difference < 0 ? "warmer" : "cooler"
        return "Scene light is \(Int(abs(difference))) K \(direction) than the stock's \(Int(balance)) K balance and records that way."
    }

    /// Reciprocity failure is a colour shift as much as a loss of speed, which is
    /// why the published compensation is a filter and not just a wider aperture.
    var reciprocityHint: String {
        let threshold = Parameter.shutterSpeed(reciprocityThresholdSeconds)
        guard settings.exposureSeconds > reciprocityThresholdSeconds else {
            return "Shorter than \(threshold), so the film records exactly what it is given: twice the time is twice the exposure."
        }
        let loss = reciprocityLossStops
        let names = ["red", "green", "blue"]
        let worst = names[loss.firstIndex(of: loss.max()!) ?? 0]
        let best = names[loss.firstIndex(of: loss.min()!) ?? 0]
        let spread = loss.max()! - loss.min()!
        var hint = String(format: "Past %@ the emulsion stops keeping what it is given: about %.1f stops lost here.",
                          threshold, loss.reduce(0, +) / 3)
        if spread > 0.05 {
            hint += String(format: " The %@ layer loses %.1f stops more than the %@ one, so the frame shifts colour as it darkens.",
                           worst, spread, best)
        }
        return hint
    }

    /// The glass sits in front of the film, so the hint has to say that it changes
    /// which colours the emulsion records as light and dark rather than tinting the
    /// result — and that its cost in light has already been paid for you.
    var contrastFilterHint: String {
        let filter = settings.contrastFilter
        let base = filter.effect + " A contrast filter multiplies the light before the film sees it, so it moves "
            + "colours apart in grey rather than colouring the picture."
        guard filter != .none, let stops = contrastFilterStops else {
            return "No glass on the lens. " + base
        }
        return String(format: "%@ Kodak's filter factor for this stock costs %.1f stops, already added back, so the "
                      + "exposure stays where you put it and only the separation changes.", base, stops)
    }

    var developmentHint: String {
        let offset = settings.developmentOffset
        let metadata = profile.metadata
        let rating = metadata.trueISO * pow(2, offset)
        // The render meters at True Speed, so a Stock the box overstates is given
        // the light it actually wants; saying so is the only way that is visible.
        let box = metadata.trueISO == metadata.nominalISO ? ""
            : " The box says \(Int(metadata.nominalISO.rounded())); this stock behaves nearer \(Int(metadata.trueISO.rounded())), and it is metered that way."
        if abs(offset) < 0.05 { return "Rated at EI \(Int(rating.rounded())) and developed normally." + box }
        let change = offset > 0 ? "raises contrast and collapses shadow separation" : "lowers contrast and opens shadows"
        return String(format: "Rated at EI %d, developed %+.1f stops. Blends the nearest baked variants; %@.",
                      Int(rating.rounded()), offset, change) + box
    }

    /// Bloom is the lens rather than the film, which is the distinction the hint has
    /// to carry: it sits next to halation and is easily mistaken for it.
    var bloomHint: String {
        let intensity = settings.bloomIntensity
        let base = "The taking lens spreads a little of every part of the scene across the frame, over about "
            + "\(Int(bloomRadiusMicrons)) µm of film. It takes that light from the scene rather than adding it, "
            + "and the film records the result, so it softens a highlight's surroundings instead of brightening them. "
            + "Halation, below, is the film reflecting light back into itself and is a different thing."
        if abs(intensity - 1) < 0.025 { return "At the modelled lens's own diffusion. " + base }
        return String(format: "At %.0f%% of the modelled lens's own diffusion. ", intensity * 100) + base
    }

    /// 100% is the Stock's own scattering, so the control reads as a departure from it.
    var halationHint: String {
        let intensity = settings.halationIntensity
        let reach = halationReachMicrons
        let base = "Light passing through the emulsion reflects off the back of the film and re-exposes it from behind, "
            + "reaching about \(Int(reach)) µm furthest in red. It happens before the density curves, not as an effect added afterwards."
        if abs(intensity - 1) < 0.025 { return "At this stock's own strength. " + base }
        return String(format: "At %.0f%% of this stock's own strength. ", intensity * 100) + base
    }

    /// 100% is the Stock's own granularity, and the pixel pitch is what decides
    /// whether the Preview resolves that as texture at all.
    var grainHint: String {
        let radius = grainRadiusMicrons
        let intensity = settings.grainIntensity
        var base = "Grain is applied in density space, after the film response and before the scan, so the scan acts on it "
            + "the way it would on real film. It is loudest in the midtones and quiet in deep shadow and blown highlight."
        if let pitch = previewPitchMicrons {
            base += pitch > 2 * radius
                ? String(format: " One preview pixel covers %.0f µm of film, wider than the %.1f µm crystals, "
                         + "so what you see is their fluctuation within a pixel; a full-resolution export "
                         + "resolves more of it.", pitch, radius)
                : " The preview resolves the crystals themselves at this size."
        }
        if abs(intensity - 1) < 0.025 { return "At this stock's own granularity. " + base }
        return String(format: "At %.0f%% of this stock's own granularity. ", intensity * 100) + base
    }

    /// A Stock with no Output Stage is not offered a disabled scan-or-print choice;
    /// the copy says why there is nothing to choose and moves on to the geometry.
    func outputCardDescription(for stage: OutputStage) -> String {
        switch stage {
        case .scan: return "Densities are inverted and auto-balanced so mid-grey comes back neutral."
        case .print: return "Contrast rises, shadows close and the highlights end at paper white."
        case .none: return "Reversal film is the final image."
        }
    }

    var outputDescription: String { outputDescription(for: outputStage) }

    func outputDescription(for stage: OutputStage) -> String {
        if isIdentity { return "Nothing happens after the identity response; the image is converted for the display." }
        switch stage {
        case .scan: return "The negative is scanned: densities are inverted and auto-balanced so mid-grey comes back neutral, the way most people picture this stock."
            + (outputStages.isEmpty ? "" : " A print of the same negative is a different picture, not a filter over this one.")
        case .print: return "The negative is enlarged onto RA-4 colour paper. The enlarger's filter pack is set so mid-grey prints neutral, "
            + "and the paper's own curve is far steeper than a scanner's, so contrast rises, shadows close and the highlights end at paper white "
            + "instead of rolling off. It is not a corrected scan; it is what the negative looks like printed."
        case .none: return "Reversal film is the final image: what the camera exposed is what you look at. There is nothing to scan or print, "
            + "so there is no choice to make here — and only about five stops fit on the film, so highlights end at clear film rather than rolling off."
        }
    }
}

// MARK: - Preview

/// Every parameter every Stock offers, as the deck will read them. This is the
/// ticket's evidence: a range, a step, a detent or a caption that regressed in the
/// lift out of the editor is visible here beside the Stock it belongs to.
private struct ParameterCatalogue: View {
    @State private var model = EditorModel()
    private let stocks = ["identity", "tri-x-400", "velvia-50", "portra-400"]

    var body: some View {
        NavigationStack {
            List {
                Picker("Stock", selection: $model.selectedStock) {
                    ForEach(stocks, id: \.self) { Text($0) }
                }
                ForEach(EditorStage.allCases) { stage in
                    Section(stage.displayName) {
                        let parameters = model.parameters(for: stage)
                        if parameters.isEmpty {
                            Text("No parameters").foregroundStyle(.secondary)
                        }
                        ForEach(parameters) { row($0) }
                    }
                }
            }
            .navigationTitle("Parameters")
        }
        .task { model.loadCatalogue() }
    }

    private func row(_ parameter: Parameter) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(parameter.name).font(.subheadline.weight(.medium))
                Spacer()
                Text(parameter.readout).font(.subheadline.monospacedDigit())
                if let tag = parameter.tag {
                    Text(tag == .off ? "● OFF" : "● DETENT").font(.caption2.monospaced()).foregroundStyle(.tint)
                }
            }
            Text(String(format: "%@ · %.4g…%.4g · step %.4g · detent %@", String(describing: parameter.control),
                        parameter.range.lowerBound, parameter.range.upperBound, parameter.step,
                        parameter.detent.map { String(format: "%.4g", $0) } ?? "—"))
                .font(.caption2.monospaced()).foregroundStyle(.secondary)
            Slider(value: parameter.value, in: parameter.range, step: parameter.step)
            if let caption = parameter.captionText {
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("Parameters") {
    ParameterCatalogue()
}
