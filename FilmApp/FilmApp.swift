import SwiftUI
import PhotosUI
import SwiftData
import FilmEngine

@main
struct FilmApp: App {
    var body: some Scene { WindowGroup { EditorView() }.modelContainer(for: Preset.self) }
}

/// Controls are laid out in pipeline order: what happened to the light before the
/// film, the Film Response itself, then what happens to the negative afterwards.
struct EditorView: View {
    @State private var model = EditorModel()
    @State private var selection: PhotosPickerItem?
    @State private var isExporting = false
    @State private var showsPresets = false
    @State private var showsContactSheet = false
    @GestureState private var holdingBefore = false
    @State private var accessibleBefore = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    canvas
                    if let error = model.error {
                        Text(error).foregroundStyle(.red).font(.footnote).accessibilityLabel("Error: \(error)")
                    }
                    StageCard(number: 1, title: "Before the film", subtitle: "Light as it reached the emulsion on the day") {
                        exposureControls
                    }
                    StageArrow()
                    StageCard(number: 2, title: "Film response", subtitle: filmSubtitle) {
                        filmControls
                    }
                    StageArrow()
                    StageCard(number: 3, title: "After the film", subtitle: outputSubtitle) {
                        outputControls
                    }
                }
                .padding()
            }
            .navigationTitle("Dye")
            .toolbar {
                ToolbarItem(placement: .secondaryAction) {
                    Button("Presets") { showsPresets = true }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Contact Sheet") { showsContactSheet = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    PhotosPicker(selection: $selection, matching: .images, preferredItemEncoding: .current) {
                        Label("Choose photo", systemImage: "photo")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { isExporting = true } label: { Label("Export", systemImage: "square.and.arrow.up") }
                        .disabled(!model.canExport && !model.isExporting)
                }
            }
            .sheet(isPresented: $showsPresets) { PresetSheet(model: model) }
            .sheet(isPresented: $showsContactSheet) { ContactSheetView() }
            .onChange(of: selection) { accessibleBefore = false }
            .sheet(isPresented: $isExporting) { ExportSheet(model: model) }
            .task { model.loadCatalogue() }
            .task { await model.watchThermalState() }
            .task(id: selection) {
                guard let selection else { return }
                await model.open(selection)
            }
        }
    }

    @ViewBuilder private var canvas: some View {
        if let pixels = model.pixels {
            FilmCanvas(image: (holdingBefore || accessibleBefore) ? (model.beforePixels ?? pixels) : pixels)
                .gesture(LongPressGesture(minimumDuration: 0.15).sequenced(before: DragGesture(minimumDistance: 0))
                    .updating($holdingBefore) { value, state, _ in
                        if case .second(true, _) = value { state = true }
                    })
                .accessibilityAction(named: accessibleBefore ? "Show edited photo" : "Show original photo") {
                    accessibleBefore.toggle()
                }
                .overlay(alignment: .topLeading) {
                    Text(holdingBefore || accessibleBefore ? "Original" : "Hold to compare")
                        .font(.caption).padding(6).background(.thinMaterial, in: Capsule()).padding(6)
                }
                .aspectRatio(CGFloat(pixels.width) / CGFloat(pixels.height), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Rendered photo")
                .overlay(alignment: .bottomTrailing) {
                    if let ms = model.lastRenderMilliseconds {
                        Text("\(ms, specifier: "%.0f") ms").font(.caption2.monospacedDigit())
                            .padding(4).background(.thinMaterial, in: Capsule()).padding(6)
                    }
                }
        } else if model.isLoading {
            ProgressView("Decoding…").frame(maxWidth: .infinity, minHeight: 240)
        } else {
            ContentUnavailableView("Open a photo", systemImage: "photo", description: Text("Choose a photo to begin."))
                .frame(minHeight: 240)
        }
    }

    private var exposureControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledSlider(title: "Exposure", value: $model.settings.exposureStops, range: -3...3, step: 1 / 6,
                          format: { String(format: "%+.1f EV", $0) })
            LabeledSlider(title: "Temperature", value: $model.settings.temperatureKelvin, range: 2000...10000, step: 50,
                          format: { String(format: "%.0f K", $0) })
            Text(balanceHint).font(.caption).foregroundStyle(.secondary)
            LabeledSlider(title: "Tint", value: $model.settings.tint, range: -100...100, step: 1,
                          format: { $0 == 0 ? "neutral" : String(format: "%+.0f %@", $0, $0 > 0 ? "magenta" : "green") })
            if model.hasReciprocity {
                // Shutter speeds are a stop apart, so the control moves in stops and
                // the label says the time. A stock that obeys reciprocity throughout
                // has no such control at all rather than a control that does nothing.
                LabeledSlider(title: "Exposure time", value: exposureStopsBinding,
                              range: log2(RenderSettings.exposureSecondsRange.lowerBound)...log2(RenderSettings.exposureSecondsRange.upperBound),
                              step: 1 / 3, format: { Self.shutterSpeed(pow(2, $0)) })
                Text(reciprocityHint).font(.caption).foregroundStyle(.secondary)
            }
            Text("Exposure and white balance act on the light before it reaches the film, so they place the scene on the characteristic curve rather than brightening the result afterwards.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// The exposure time in stops, which is how a shutter speed dial is spaced.
    private var exposureStopsBinding: Binding<Double> {
        Binding(get: { log2(model.settings.exposureSeconds) },
                set: { model.settings.exposureSeconds = min(max(pow(2, $0), RenderSettings.exposureSecondsRange.lowerBound),
                                                            RenderSettings.exposureSecondsRange.upperBound) })
    }

    private static func shutterSpeed(_ seconds: Double) -> String {
        if seconds >= 1 { return seconds < 60 ? String(format: "%.0f s", seconds) : String(format: "%.0f min", seconds / 60) }
        return String(format: "1/%.0f s", 1 / seconds)
    }

    /// Reciprocity failure is a colour shift as much as a loss of speed, which is
    /// why the published compensation is a filter and not just a wider aperture.
    private var reciprocityHint: String {
        let threshold = Self.shutterSpeed(model.reciprocityThresholdSeconds)
        guard model.settings.exposureSeconds > model.reciprocityThresholdSeconds else {
            return "Shorter than \(threshold), so the film records exactly what it is given: twice the time is twice the exposure."
        }
        let loss = model.reciprocityLossStops
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

    private var filmControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach([Profile.identity] + model.catalogue) { profile in
                        Button { model.selectedStock = profile.id } label: {
                            VStack {
                                if let image = model.thumbnails[profile.id] {
                                    FilmCanvas(image: image).aspectRatio(CGFloat(image.width) / CGFloat(image.height), contentMode: .fit)
                                        .frame(width: 100, height: 80).allowsHitTesting(false)
                                } else {
                                    Image(systemName: "photo").frame(width: 100, height: 80)
                                }
                                Text(profile.metadata.displayName).font(.caption).lineLimit(2)
                            }.frame(width: 110).padding(4)
                                .background(model.selectedStock == profile.id ? Color.accentColor.opacity(0.2) : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(model.selectedStock == profile.id ? .isSelected : [])
                    }
                }
            }
            Picker("Stock", selection: $model.selectedStock) {
                Text("Identity (no film)").tag("identity")
                ForEach(FilmProcess.allCases, id: \.self) { process in
                    Section(process.displayName) {
                        ForEach(model.catalogue.filter { $0.metadata.process == process }) { profile in
                            Text(profile.metadata.isApproximation
                                 ? "\(profile.metadata.displayName) (approximation)"
                                 : profile.metadata.displayName).tag(profile.id)
                        }
                    }
                }
            }
            .pickerStyle(.menu)
            if !model.isIdentity && model.profile.metadata.isApproximation {
                Text("An approximation: this stock publishes no usable curves, so its shape is "
                     + "borrowed from a sibling stock and adjusted. Not a claim about its numbers.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let parent = model.derivedFrom {
                Text("The same emulsion as \(parent.metadata.displayName), modelled without its remjet backing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !model.contrastFilters.isEmpty {
                Picker("Contrast filter", selection: $model.settings.contrastFilter) {
                    ForEach(model.contrastFilters) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                Text(contrastFilterHint).font(.caption).foregroundStyle(.secondary)
            }
            if let range = model.developmentRange {
                LabeledSlider(title: "Development", value: $model.settings.developmentOffset, range: range, step: 0.1,
                              format: developmentLabel)
                Text(developmentHint).font(.caption).foregroundStyle(.secondary)
            }
            if model.hasBloom {
                LabeledSlider(title: "Bloom", value: $model.settings.bloomIntensity,
                              range: RenderSettings.bloomRange, step: 0.05,
                              format: { String(format: "%.0f%%", $0 * 100) })
                Text(bloomHint).font(.caption).foregroundStyle(.secondary)
            }
            if model.hasHalation {
                LabeledSlider(title: "Halation", value: $model.settings.halationIntensity,
                              range: RenderSettings.halationRange, step: 0.05,
                              format: { String(format: "%.0f%%", $0 * 100) })
                Text(halationHint).font(.caption).foregroundStyle(.secondary)
            }
            if model.hasGrain {
                LabeledSlider(title: "Grain", value: $model.settings.grainIntensity,
                              range: RenderSettings.grainRange, step: 0.05,
                              format: { String(format: "%.0f%%", $0 * 100) })
                Text(grainHint).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// The Geometry Pass is the frame and the lens rather than the film, so it sits
    /// after the negative alongside the scan.
    private var outputControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            // A negative is scanned or printed, and the two are different pictures
            // rather than different settings, so the choice leads the card instead
            // of sitting under the sliders that only trim it.
            if !model.outputStages.isEmpty {
                Picker("Read the negative by", selection: $model.outputStage) {
                    ForEach(model.outputStages, id: \.self) { stage in
                        Text(stage.displayName).tag(stage)
                    }
                }
                .pickerStyle(.segmented)
            }
            Text(outputDescription).font(.footnote).foregroundStyle(.secondary)
            LabeledSlider(title: "Vignette", value: $model.settings.vignette, range: RenderSettings.vignetteRange, step: 0.05,
                          format: { $0 == 0 ? "none" : String(format: "%.0f%%", $0 * 100) })
            LabeledSlider(title: "Gate weave", value: $model.settings.gateWeave, range: RenderSettings.gateWeaveRange, step: 0.05,
                          format: { $0 == 0 ? "steady" : String(format: "%.0f%%", $0 * 100) })
            LabeledSlider(title: "Frame border", value: $model.settings.frameBorder, range: RenderSettings.frameBorderRange, step: 0.05,
                          format: { $0 == 0 ? "none" : String(format: "%.0f%%", $0 * 100) })
            Text("The lens's own falloff, how unsteadily the frame sat in the gate, and the unexposed "
                 + "rebate around it. None of the three is a property of the stock, so all three start at zero.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var filmSubtitle: String {
        if model.isIdentity { return "No film: the Working Space passes straight through" }
        let metadata = model.profile.metadata
        let approximation = metadata.isApproximation ? " · approximation" : ""
        return "\(metadata.displayName) · \(metadata.process.displayName) · balanced for \(Int(metadata.balance)) K\(approximation)"
    }

    private var balanceHint: String {
        let balance = model.profile.metadata.balance
        let difference = model.settings.temperatureKelvin - balance
        if difference == 0 { return "Scene light matches the stock's \(Int(balance)) K balance: neutral on film." }
        let direction = difference < 0 ? "warmer" : "cooler"
        return "Scene light is \(Int(abs(difference))) K \(direction) than the stock's \(Int(balance)) K balance and records that way."
    }

    /// The glass sits in front of the film, so the hint has to say that it changes
    /// which colours the emulsion records as light and dark rather than tinting the
    /// result — and that its cost in light has already been paid for you.
    private var contrastFilterHint: String {
        let filter = model.settings.contrastFilter
        let base = filter.effect + " A contrast filter multiplies the light before the film sees it, so it moves "
            + "colours apart in grey rather than colouring the picture."
        guard filter != .none, let stops = model.contrastFilterStops else {
            return "No glass on the lens. " + base
        }
        return String(format: "%@ Kodak's filter factor for this stock costs %.1f stops, already added back, so the "
                      + "exposure stays where you put it and only the separation changes.", base, stops)
    }

    private func developmentLabel(_ offset: Double) -> String {
        if abs(offset) < 0.05 { return "normal" }
        return String(format: "%@ %+.1f", offset > 0 ? "push" : "pull", offset)
    }

    private var developmentHint: String {
        let offset = model.settings.developmentOffset
        let metadata = model.profile.metadata
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
    private var bloomHint: String {
        let intensity = model.settings.bloomIntensity
        let base = "The taking lens spreads a little of every part of the scene across the frame, over about "
            + "\(Int(model.bloomRadiusMicrons)) µm of film. It takes that light from the scene rather than adding it, "
            + "and the film records the result, so it softens a highlight's surroundings instead of brightening them. "
            + "Halation, below, is the film reflecting light back into itself and is a different thing."
        if abs(intensity - 1) < 0.025 { return "At the modelled lens's own diffusion. " + base }
        return String(format: "At %.0f%% of the modelled lens's own diffusion. ", intensity * 100) + base
    }

    /// 100% is the Stock's own scattering, so the control reads as a departure from it.
    private var halationHint: String {
        let intensity = model.settings.halationIntensity
        let reach = model.halationReachMicrons
        let base = "Light passing through the emulsion reflects off the back of the film and re-exposes it from behind, "
            + "reaching about \(Int(reach)) µm furthest in red. It happens before the density curves, not as an effect added afterwards."
        if abs(intensity - 1) < 0.025 { return "At this stock's own strength. " + base }
        return String(format: "At %.0f%% of this stock's own strength. ", intensity * 100) + base
    }

    /// 100% is the Stock's own granularity, and the pixel pitch is what decides
    /// whether the Preview resolves that as texture at all.
    private var grainHint: String {
        let radius = model.grainRadiusMicrons
        let intensity = model.settings.grainIntensity
        var base = "Grain is applied in density space, after the film response and before the scan, so the scan acts on it "
            + "the way it would on real film. It is loudest in the midtones and quiet in deep shadow and blown highlight."
        if let pitch = model.previewPitchMicrons {
            base += pitch > 2 * radius
                ? String(format: " One preview pixel covers %.0f µm of film, wider than the %.1f µm crystals, "
                         + "so what you see is their fluctuation within a pixel; a full-resolution export "
                         + "resolves more of it.", pitch, radius)
                : " The preview resolves the crystals themselves at this size."
        }
        if abs(intensity - 1) < 0.025 { return "At this stock's own granularity. " + base }
        return String(format: "At %.0f%% of this stock's own granularity. ", intensity * 100) + base
    }

    private var outputSubtitle: String {
        if model.isIdentity { return "Display P3" }
        switch model.outputStage {
        case .scan: return "Scan · Display P3"
        case .print: return "Print · Display P3"
        case .none: return "Reversal · Display P3"
        }
    }

    /// A Stock with no Output Stage is not offered a disabled scan-or-print choice;
    /// the card says why there is nothing to choose and moves on to the geometry.
    private var outputDescription: String {
        if model.isIdentity { return "Nothing happens after the identity response; the image is converted for the display." }
        switch model.outputStage {
        case .scan: return "The negative is scanned: densities are inverted and auto-balanced so mid-grey comes back neutral, the way most people picture this stock."
            + (model.outputStages.isEmpty ? "" : " A print of the same negative is a different picture, not a filter over this one.")
        case .print: return "The negative is enlarged onto RA-4 colour paper. The enlarger's filter pack is set so mid-grey prints neutral, "
            + "and the paper's own curve is far steeper than a scanner's, so contrast rises, shadows close and the highlights end at paper white "
            + "instead of rolling off. It is not a corrected scan; it is what the negative looks like printed."
        case .none: return "Reversal film is the final image: what the camera exposed is what you look at. There is nothing to scan or print, "
            + "so there is no choice to make here — and only about five stops fit on the film, so highlights end at clear film rather than rolling off."
        }
    }
}

private struct StageCard<Content: View>: View {
    let number: Int
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(number)").font(.headline.monospacedDigit())
                    .frame(width: 28, height: 28).background(Circle().fill(.tint))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stage \(number): \(title)")
    }
}

private struct StageArrow: View {
    var body: some View {
        Image(systemName: "arrow.down").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value)).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.subheadline)
            Slider(value: $value, in: range, step: step) { Text(title) }
        }
    }
}
