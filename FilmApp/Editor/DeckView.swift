import SwiftUI
import FilmEngine

struct DeckView: View {
    let model: EditorModel
    let selection: EditorSelection
    let hasPhoto: Bool
    @Binding var photo: PickedPhoto?
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
                .padding(.top, 8)
                .padding(.bottom, 8)
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
        .frame(minHeight: Tokens.Deck.height + Tokens.Deck.extraHeight(for: dynamicTypeSize), alignment: .top)
        .background(Tokens.Palette.deck.ignoresSafeArea(edges: .bottom))
        .onChange(of: parameters.map(\.id), initial: true) { selection.reconcile(with: model.dialParameters) }

    }

    private var groupMenu: some View {
        Menu {
            ForEach(EditorStage.allCases) { stage in
                Button(stage.displayName) { selection.select(stage) }
                    .disabled(!model.dialParameters.contains { $0.stage == stage })
            }
        } label: {
            HStack(spacing: 4) {
                Text(selection.stage.displayName)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }
                .contentTransition(.opacity)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.09), value: selection.stage)
                .font(.subheadline)
                .foregroundStyle(Tokens.Palette.textSecondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Jump to stage")
        .accessibilityValue(selection.stage.displayName)
        .disabled(!hasPhoto)
    }

    private func parameterName(_ parameter: Parameter?) -> some View {
        Text(parameter?.name ?? "Choose a photo")
            .font(.subheadline.weight(.medium))
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

/// Interactive acceptance fixture. The deck grows with its toolbar labels and
/// Dynamic Type instead of clipping controls to a fixed height.
struct DeckPreview: View {
    @State private var model = EditorModel()
    @State private var selection = EditorSelection()
    @State private var photo: PickedPhoto?
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
            EditorPickers(model: model, selection: selection, hasPhoto: hasPhoto)
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

#Preview("274 pt · Linen · Film") { DeckPreview().preferredColorScheme(.dark) }
#Preview("274 pt · Newsprint · Film") { DeckPreview(stock: "tri-x-400").preferredColorScheme(.dark) }
#Preview("274 pt · Vermilion · Lab") { DeckPreview(stock: "velvia-50", stage: .lab).preferredColorScheme(.dark) }
#Preview("274 pt · No Film Stock · Lab") { DeckPreview(stock: "identity", stage: .lab).preferredColorScheme(.dark) }
#Preview("274 pt · Linen · Adjust") { DeckPreview(stage: .adjust).preferredColorScheme(.dark) }
#Preview("274 pt · Velvia · Adjust") { DeckPreview(stock: "velvia-50", stage: .adjust).preferredColorScheme(.dark) }

#Preview("274 pt · No photo") { DeckPreview(photoLoaded: false).preferredColorScheme(.dark) }

#Preview("344 pt · largest text · all Stocks") {
    DeckPreview().dynamicTypeSize(.accessibility5)
        .preferredColorScheme(.dark)
}
#Preview("344 pt · largest text · no photo") {
    DeckPreview(photoLoaded: false).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark)
}
#Preview("344 pt · largest text · filmstrip") {
    DeckPreview(filmstripOpen: true).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark)
}
