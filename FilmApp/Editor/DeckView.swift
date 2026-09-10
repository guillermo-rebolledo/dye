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
        let parameters = model.allParameters
        let active = selection.activeParameter(in: parameters)
        VStack(spacing: 0) {
            groupMenu.frame(height: 20)
            ActiveControl(parameter: active, model: model, isEnabled: hasPhoto)
                .padding(.horizontal, 16).frame(height: 34)
            Group {
                if hasPhoto && active?.control == .filmstrip {
                    Filmstrip(catalogue: model.catalogue, thumbnails: model.thumbnails,
                              selectedStock: Binding(get: { model.selectedStock }, set: { model.selectedStock = $0 }),
                              close: { selection.move(1) })
                } else if hasPhoto && active?.control == .outputStageCards {
                    VStack(spacing: 8) {
                        OutputStageCards(model: model).padding(.horizontal, 16)
                        Button("Continue to controls") { selection.move(1) }
                            .font(.system(size: 11)).foregroundStyle(Tokens.Palette.textPrimary)
                            .frame(height: 44)
                    }
                } else {
                    VStack(spacing: 0) {
                        ParameterRail(model: model, selection: selection, parameters: parameters)
                            .disabled(!hasPhoto)
                        parameterName(active).frame(height: 24 + Tokens.Deck.extraHeight(for: dynamicTypeSize))
                        ActiveControl(parameter: active, model: model, isEnabled: hasPhoto,
                                      showsTrack: true, onDragging: onDragging)
                            .frame(height: 44)
                    }
                }
            }
            .frame(height: 140 + Tokens.Deck.extraHeight(for: dynamicTypeSize))
            ActionRow(photo: $photo, hasPhoto: hasPhoto, canExport: model.canExport || model.isExporting,
                      showPresets: showPresets, showContactSheet: showContactSheet, showExport: showExport,
                      isLoupeEnabled: $isLoupeEnabled)
                .padding(.horizontal, 16)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Tokens.Deck.height + Tokens.Deck.extraHeight(for: dynamicTypeSize), alignment: .top)
        .background(Tokens.Palette.deck.ignoresSafeArea(edges: .bottom))
        .onChange(of: parameters.map(\.id), initial: true) { selection.reconcile(with: model.allParameters) }
    }

    private var groupTitle: String {
        if selection.isFilmstripOpen { return "FILM · STOCK" }
        if selection.stage == .film { return "FILM · " + model.profile.metadata.displayName.uppercased() }
        return selection.stage.displayName.uppercased()
    }

    private var groupMenu: some View {
        Menu {
            ForEach(EditorStage.allCases) { stage in
                Button(stage.displayName) { selection.select(stage) }
                    .disabled(model.parameters(for: stage).isEmpty)
            }
        } label: {
            Text(groupTitle)
                .contentTransition(.opacity)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.09), value: selection.stage)
                .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 12 : 10, design: .monospaced))
                .tracking(1.4).lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(Tokens.Palette.textPrimary.opacity(0.42))
                .frame(maxWidth: .infinity, minHeight: 20)
                .contentShape(Rectangle().inset(by: -12))
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
/// photo availability, stage and takeover presentation.
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
        .task { model.loadCatalogue(); model.selectedStock = stock; selection.reconcile(with: model.allParameters); selection.select(stage); hasPhoto = photoLoaded; selection.isFilmstripOpen = filmstripOpen }
    }
}

#Preview("262 pt · Portra · Film") { DeckPreview().preferredColorScheme(.dark) }
#Preview("262 pt · Tri-X · Film") { DeckPreview(stock: "tri-x-400").preferredColorScheme(.dark) }
#Preview("262 pt · Velvia · Lab") { DeckPreview(stock: "velvia-50", stage: .lab).preferredColorScheme(.dark) }
#Preview("262 pt · Identity · Lab") { DeckPreview(stock: "identity", stage: .lab).preferredColorScheme(.dark) }
#Preview("262 pt · Portra · Adjust") { DeckPreview(stage: .adjust).preferredColorScheme(.dark) }
#Preview("262 pt · Velvia · Adjust") { DeckPreview(stock: "velvia-50", stage: .adjust).preferredColorScheme(.dark) }

#Preview("262 pt · No photo") { DeckPreview(photoLoaded: false).preferredColorScheme(.dark) }

#Preview("276 pt · largest text · all Stocks") {
    DeckPreview().dynamicTypeSize(.accessibility5)
        .preferredColorScheme(.dark)
}
#Preview("276 pt · largest text · no photo") {
    DeckPreview(photoLoaded: false).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark)
}
#Preview("276 pt · largest text · filmstrip") {
    DeckPreview(filmstripOpen: true).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark)
}
