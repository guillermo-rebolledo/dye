import SwiftUI
import PhotosUI
import FilmEngine

@main
struct FilmApp: App {
    var body: some Scene { WindowGroup { EditorView() } }
}

/// Controls are laid out in pipeline order: what happened to the light before the
/// film, the Film Response itself, then what happens to the negative afterwards.
struct EditorView: View {
    @State private var model = EditorModel()
    @State private var selection: PhotosPickerItem?

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
                PhotosPicker(selection: $selection, matching: .images, preferredItemEncoding: .current) {
                    Label("Choose photo", systemImage: "photo")
                }
            }
            .task { model.loadCatalogue() }
            .task(id: selection) {
                guard let selection else { return }
                await model.open(selection)
            }
        }
    }

    @ViewBuilder private var canvas: some View {
        if let pixels = model.pixels {
            FilmCanvas(image: pixels)
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
            Text("Exposure and white balance act on the light before it reaches the film, so they place the scene on the characteristic curve rather than brightening the result afterwards.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var filmControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Stock", selection: $model.selectedStock) {
                Text("Identity (no film)").tag("identity")
                ForEach(FilmProcess.allCases, id: \.self) { process in
                    Section(process.displayName) {
                        ForEach(model.catalogue.filter { $0.metadata.process == process }) { profile in
                            Text(profile.metadata.displayName).tag(profile.id)
                        }
                    }
                }
            }
            .pickerStyle(.menu)
            if let parent = model.derivedFrom {
                Text("The same emulsion as \(parent.metadata.displayName), modelled without its remjet backing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let range = model.developmentRange {
                LabeledSlider(title: "Development", value: $model.settings.developmentOffset, range: range, step: 0.1,
                              format: developmentLabel)
                Text(developmentHint).font(.caption).foregroundStyle(.secondary)
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
        return "\(metadata.displayName) · \(metadata.process.displayName) · balanced for \(Int(metadata.balance)) K"
    }

    private var balanceHint: String {
        let balance = model.profile.metadata.balance
        let difference = model.settings.temperatureKelvin - balance
        if difference == 0 { return "Scene light matches the stock's \(Int(balance)) K balance: neutral on film." }
        let direction = difference < 0 ? "warmer" : "cooler"
        return "Scene light is \(Int(abs(difference))) K \(direction) than the stock's \(Int(balance)) K balance and records that way."
    }

    private func developmentLabel(_ offset: Double) -> String {
        if abs(offset) < 0.05 { return "normal" }
        return String(format: "%@ %+.1f", offset > 0 ? "push" : "pull", offset)
    }

    private var developmentHint: String {
        let offset = model.settings.developmentOffset
        let rating = model.profile.metadata.trueISO * pow(2, offset)
        if abs(offset) < 0.05 { return "Rated at EI \(Int(rating.rounded())) and developed normally." }
        let change = offset > 0 ? "raises contrast and collapses shadow separation" : "lowers contrast and opens shadows"
        return String(format: "Rated at EI %d, developed %+.1f stops. Blends the nearest baked variants; %@.", Int(rating.rounded()), offset, change)
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
        switch model.profile.metadata.colour.outputStage {
        case .scan: return "Scan · Display P3"
        case .print: return "Print · Display P3"
        case .none: return "Reversal · Display P3"
        }
    }

    private var outputDescription: String {
        if model.isIdentity { return "Nothing happens after the identity response; the image is converted for the display." }
        switch model.profile.metadata.colour.outputStage {
        case .scan: return "The negative is scanned: densities are inverted and auto-balanced so mid-grey comes back neutral, the way most people picture this stock."
        case .print: return "Optical print emulation is not available yet."
        case .none: return "Reversal film is the final image; there is no scan or print stage."
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
