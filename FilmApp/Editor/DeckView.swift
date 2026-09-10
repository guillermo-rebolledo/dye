import SwiftUI
import PhotosUI
import FilmEngine

struct DeckView: View {
    let model: EditorModel
    let selection: EditorSelection
    let hasPhoto: Bool
    @Binding var photo: PhotosPickerItem?
    @Binding var isLoupeEnabled: Bool
    let showPresets: () -> Void
    let showContactSheet: () -> Void
    let showExport: () -> Void
    var onDragging: (Bool) -> Void = { _ in }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let parameters = model.dialParameters
        let active = selection.activeParameter(in: parameters)
        VStack(spacing: 0) {
            stockHeader
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 112 : 56)
            ActiveControl(parameter: active, model: model, isEnabled: hasPhoto)
                .padding(.horizontal, 16).frame(height: 34)
            ParameterRail(model: model, selection: selection, parameters: parameters)
                .disabled(!hasPhoto)
            HStack(spacing: 8) {
                groupMenu
                parameterName(active)
            }
            .padding(.horizontal, 16)
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 58 : 44)
            ActiveControl(parameter: active, model: model, isEnabled: hasPhoto,
                          showsTrack: true, onDragging: onDragging)
                .frame(height: 44)
            ActionRow(photo: $photo, hasPhoto: hasPhoto, canExport: model.canExport || model.isExporting,
                      showPresets: showPresets, showContactSheet: showContactSheet, showExport: showExport,
                      isLoupeEnabled: $isLoupeEnabled)
                .padding(.horizontal, 16)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Tokens.Deck.height + Tokens.Deck.extraHeight(for: dynamicTypeSize), alignment: .top)
        .background(Tokens.Palette.deck.ignoresSafeArea(edges: .bottom))
        .onChange(of: parameters.map(\.id), initial: true) { selection.reconcile(with: model.dialParameters) }
        .sheet(isPresented: Binding(get: { selection.isFilmstripOpen }, set: { selection.isFilmstripOpen = $0 })) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Stock").font(.title2.bold())
                Text(model.profile.metadata.displayName).font(.headline)
                Filmstrip(catalogue: model.catalogue, thumbnails: model.thumbnails,
                          selectedStock: Binding(get: { model.selectedStock }, set: { model.selectedStock = $0 }),
                          close: { selection.isFilmstripOpen = false })
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 16)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Tokens.Palette.deck)
        }
        .sheet(isPresented: Binding(get: { selection.isOutputBrowserOpen }, set: { selection.isOutputBrowserOpen = $0 })) {
            VStack(spacing: 24) {
                Text("Output").font(.title2.bold())
                OutputStageCards(model: model)
                Button("Done") { selection.isOutputBrowserOpen = false }
                    .frame(minHeight: 44)
            }
            .padding(24)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Tokens.Palette.deck)
        }
    }

    private var stockHeader: some View {
        HStack(spacing: 12) {
            Button { selection.isFilmstripOpen = true } label: {
                HStack(spacing: 10) {
                    Group {
                        if let pixels = model.thumbnails[model.selectedStock] {
                            FilmCanvas(image: pixels)
                                .aspectRatio(CGFloat(pixels.width) / CGFloat(pixels.height), contentMode: .fill)
                        } else { DevelopingFrame(showsCaption: false) }
                    }
                    .frame(width: 40, height: 40).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.profile.metadata.displayName)
                            .font(.headline).lineLimit(2)
                        Text(model.selectedStock == "identity" ? "No stock response" : model.profile.metadata.process.displayName)
                            .font(.caption).foregroundStyle(Tokens.Deck.captionInk)
                            .lineLimit(2)
                    }
                    Image(systemName: "chevron.down").font(.caption)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stock")
            .accessibilityValue(model.profile.metadata.displayName)
            .accessibilityHint("Browse stocks")
            if !model.outputStages.isEmpty {
                Button { selection.isOutputBrowserOpen = true } label: {
                    VStack(spacing: 3) {
                        Text(model.outputStage.displayName).font(.subheadline)
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Output")
                .accessibilityValue(model.outputStage.displayName)
            }
        }
        .foregroundStyle(Tokens.Palette.textPrimary)
        .padding(.horizontal, 16)
        .disabled(!hasPhoto)
    }

    private var groupMenu: some View {
        Menu {
            ForEach(EditorStage.allCases) { stage in
                Button(stage.displayName) { selection.select(stage) }
                    .disabled(!model.dialParameters.contains { $0.stage == stage })
            }
        } label: {
            Text(selection.stage.displayName.uppercased())
                .contentTransition(.opacity)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.09), value: selection.stage)
                .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 12 : 10, design: .monospaced))
                .tracking(1.4).lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(Tokens.Palette.textPrimary.opacity(0.42))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Jump to stage")
        .accessibilityValue(selection.stage.displayName)
        .disabled(!hasPhoto)
    }

    private func parameterName(_ parameter: Parameter?) -> some View {
        Text(parameter?.name ?? "Choose a photo")
            .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 14 : 11))
            .foregroundStyle(Tokens.Palette.textPrimary)
            .frame(maxWidth: .infinity).contentShape(Rectangle())
            .gesture(LongPressGesture().onEnded { _ in reset(parameter) }
                .exclusively(before: TapGesture(count: 2).onEnded { reset(parameter) }))
            .accessibilityAction(named: "Reset to default") { reset(parameter) }
    }

    private func reset(_ parameter: Parameter?) {
        guard hasPhoto, let parameter else { return }
        Haptics.reset()
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.16)) {
            parameter.value.wrappedValue = parameter.defaultValue
        }
    }
}

/// Interactive acceptance fixture. The measured height is independent of Stock,
/// photo availability, stage and browser presentation.
struct DeckPreview: View {
    @State private var model = EditorModel()
    @State private var selection = EditorSelection()
    @State private var photo: PhotosPickerItem?
    @State private var loupe = false
    @State private var hasPhoto = true
    @State private var measuredHeight: CGFloat = 0
    @State private var sheet: String?
    var stock = "portra-400"
    var stage: EditorStage = .film
    var photoLoaded = true
    var filmstripOpen = false

    var body: some View {
        VStack(spacing: Tokens.Metrics.space16) {
            Picker("Stock", selection: $model.selectedStock) {
                ForEach(model.catalogueWithIdentity) { Text($0.metadata.displayName).tag($0.id) }
            }
            Toggle("Photo loaded", isOn: $hasPhoto)
            Toggle("Filmstrip requested", isOn: $selection.isFilmstripOpen)
            Text("Deck: \(measuredHeight, specifier: "%.0f") pt").typeStyle(.unit)
            Spacer(minLength: 0)
            DeckView(model: model, selection: selection, hasPhoto: hasPhoto,
                     photo: $photo, isLoupeEnabled: $loupe,
                     showPresets: { sheet = "Presets" }, showContactSheet: { sheet = "Contact Sheet" },
                     showExport: { sheet = "Export" })
                .background(GeometryReader { proxy in
                    Color.clear.onAppear { measuredHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, height in measuredHeight = height }
                })
        }
        .background(Tokens.Palette.canvas)
        .foregroundStyle(Tokens.Palette.textPrimary)
        .sheet(isPresented: Binding(get: { sheet != nil }, set: { if !$0 { sheet = nil } })) {
            Text(sheet ?? "")
        }
        .task { await model.loadCatalogue(); model.selectedStock = stock; selection.reconcile(with: model.dialParameters); selection.select(stage); hasPhoto = photoLoaded; selection.isFilmstripOpen = filmstripOpen }
    }
}

#Preview("318 pt · Portra · Film") { DeckPreview().preferredColorScheme(.dark) }
#Preview("318 pt · Tri-X · Film") { DeckPreview(stock: "tri-x-400").preferredColorScheme(.dark) }
#Preview("318 pt · Velvia · Lab") { DeckPreview(stock: "velvia-50", stage: .lab).preferredColorScheme(.dark) }
#Preview("318 pt · Identity · Lab") { DeckPreview(stock: "identity", stage: .lab).preferredColorScheme(.dark) }
#Preview("318 pt · Portra · Adjust") { DeckPreview(stage: .adjust).preferredColorScheme(.dark) }
#Preview("318 pt · Velvia · Adjust") { DeckPreview(stock: "velvia-50", stage: .adjust).preferredColorScheme(.dark) }

#Preview("318 pt · No photo") { DeckPreview(photoLoaded: false).preferredColorScheme(.dark) }

#Preview("388 pt · largest text · all Stocks") {
    DeckPreview().dynamicTypeSize(.accessibility5)
        .preferredColorScheme(.dark)
}
#Preview("388 pt · largest text · no photo") {
    DeckPreview(photoLoaded: false).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark)
}
#Preview("388 pt · largest text · filmstrip") {
    DeckPreview(filmstripOpen: true).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark)
}
