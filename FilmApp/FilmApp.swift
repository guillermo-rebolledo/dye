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
            ForEach(model.parameters(for: .light)) { control($0) }
            Text("Exposure and white balance act on the light before it reaches the film, so they place the scene on the characteristic curve rather than brightening the result afterwards.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// One parameter as this screen has always drawn it: the control it names,
    /// then its caption. Everything that decided the range, the step, the format
    /// and the copy now lives in `Parameter`, so this is the whole of it. The deck
    /// draws the same parameters through the scrubber, the discs and the cards.
    @ViewBuilder private func control(_ parameter: Parameter) -> some View {
        switch parameter.control {
        case .scrubber, .shutterDial:
            LabeledSlider(title: parameter.name, value: parameter.value, range: parameter.range,
                          step: parameter.step, format: parameter.format)
        case .contrastFilterDiscs:
            Picker(parameter.name, selection: $model.settings.contrastFilter) {
                ForEach(model.contrastFilters) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.menu)
        case .outputStageCards:
            Picker(parameter.name, selection: $model.outputStage) {
                ForEach(model.outputStages, id: \.self) { stage in
                    Text(stage.displayName).tag(stage)
                }
            }
            .pickerStyle(.segmented)
        }
        if let caption = parameter.captionText {
            // The Output Stage's copy leads its stage rather than trailing a
            // slider, and reads a size larger for it. The deck gives every caption
            // one 28 pt slot; until then this keeps the old screen as it was.
            Text(caption).font(parameter.id == .outputStage ? .footnote : .caption)
                .foregroundStyle(.secondary)
        }
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
            ForEach(model.parameters(for: .film)) { control($0) }
        }
    }

    /// The Geometry Pass is the frame and the lens rather than the film, so it sits
    /// after the negative alongside the scan.
    private var outputControls: some View {
        let parameters = model.parameters(for: .lab)
        return VStack(alignment: .leading, spacing: 14) {
            // A Stock with no Output Stage is offered no scan-or-print choice, but
            // still says why there is nothing to choose. With a choice the same
            // copy is the parameter's own caption and is drawn under the control.
            if !parameters.contains(where: { $0.id == .outputStage }) {
                Text(model.outputDescription).font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(parameters) { control($0) }
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

    private var outputSubtitle: String {
        if model.isIdentity { return "Display P3" }
        switch model.outputStage {
        case .scan: return "Scan · Display P3"
        case .print: return "Print · Display P3"
        case .none: return "Reversal · Display P3"
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
