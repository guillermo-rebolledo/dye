import SwiftUI
import PhotosUI

/// The deck owns no render state. The editor supplies photo and presentation
/// bindings; the editor places this shell below the canvas.
struct DeckView: View {
    let model: EditorModel
    let selection: EditorSelection
    let hasPhoto: Bool
    @Binding var photo: PhotosPickerItem?
    @Binding var isLoupeEnabled: Bool
    let showPresets: () -> Void
    let showContactSheet: () -> Void
    let showExport: () -> Void
    var error: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let parameters = model.parameters(for: selection.stage)
        VStack(spacing: Tokens.Metrics.space10) {
            StageSelector(selection: selection)
                .disabled(!hasPhoto)
                .opacity(hasPhoto ? 1 : Tokens.Deck.unavailableOpacity)
            Text(subLabel).typeStyle(.subLabel).foregroundStyle(Tokens.Deck.quietInk)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity)
                .frame(height: Tokens.Deck.subLabelHeight)
            Group {
                if selection.isFilmstripOpen && hasPhoto {
                    Filmstrip(catalogue: model.catalogue, thumbnails: model.thumbnails,
                              selectedStock: Binding(get: { model.selectedStock }, set: { model.selectedStock = $0 }),
                              close: { selection.isFilmstripOpen = false })
                        .padding(.horizontal, -Tokens.Metrics.space16)
                } else {
                    VStack(spacing: Tokens.Metrics.space10) {
                        ParameterRow(model: model, selection: selection, isEnabled: hasPhoto)
                        ActiveControl(parameter: selection.activeParameter(in: parameters), model: model,
                                      isEnabled: hasPhoto, error: error ?? model.error)
                    }
                }
            }
            .frame(height: Tokens.Filmstrip.height)
            .id(selection.stage)
            .transition(.asymmetric(
                insertion: .offset(x: reduceMotion ? 0 : Tokens.Motion.stageSlide).combined(with: .opacity),
                removal: .offset(x: reduceMotion ? 0 : -Tokens.Motion.stageSlide).combined(with: .opacity)))
            .animation(Tokens.Motion.ease(Tokens.Motion.stageSwitch, reduceMotion: reduceMotion), value: selection.stage)
            ActionRow(photo: $photo, hasPhoto: hasPhoto, canExport: model.canExport || model.isExporting,
                      showPresets: showPresets, showContactSheet: showContactSheet, showExport: showExport,
                      isLoupeEnabled: $isLoupeEnabled)
        }
        .padding(.top, Tokens.Metrics.space10)
        .padding(.horizontal, Tokens.Metrics.space16)
        // The remaining 30 pt are the fixed bottom gutter. Background extends
        // through the device's home-indicator safe area without moving contents.
        .frame(maxWidth: .infinity)
        .frame(height: Tokens.Deck.height, alignment: .top)
        .background(Tokens.Palette.deck.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Tokens.Deck.border.frame(height: Tokens.Elevation.hairlineWidth) }
        .onChange(of: parameters.map(\.id), initial: true) {
            selection.reconcile(with: model.parameters(for: selection.stage))
        }
    }

    private var subLabel: String {
        guard hasPhoto else { return "No photo loaded" }
        switch selection.stage {
        case .light: return "Light as it reached the emulsion on the day."
        case .film:
            if model.isIdentity { return "No film: the working space passes straight through" }
            let metadata = model.profile.metadata
            let approximation = metadata.isApproximation ? " · approximation" : ""
            return "\(metadata.displayName) · \(metadata.process.displayName) · balanced for \(Int(metadata.balance)) K\(approximation)"
        case .lab:
            if model.isIdentity { return "Display P3" }
            switch model.outputStage {
            case .scan: return "Scan · Display P3"
            case .print: return "Print · enlarged onto RA-4 paper · Display P3"
            case .none: return "Reversal · the film is the final image · nothing to scan or print"
            }
        }
    }
}

/// Interactive acceptance fixture. The measured height is independent of Stock,
/// caption, photo availability, stage and the filmstrip presentation.
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
                ForEach(["tri-x-400", "velvia-50", "portra-400", "identity"], id: \.self) { Text($0).tag($0) }
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
        .task { model.loadCatalogue(); model.selectedStock = stock; selection.select(stage); hasPhoto = photoLoaded; selection.isFilmstripOpen = filmstripOpen }
    }
}

#Preview("316 pt · Portra · Film") { DeckPreview().preferredColorScheme(.dark) }
#Preview("316 pt · Tri-X · Film") { DeckPreview(stock: "tri-x-400").preferredColorScheme(.dark) }
#Preview("316 pt · Velvia · Lab") { DeckPreview(stock: "velvia-50", stage: .lab).preferredColorScheme(.dark) }
#Preview("316 pt · Identity · Lab") { DeckPreview(stock: "identity", stage: .lab).preferredColorScheme(.dark) }

#Preview("316 pt · No photo") { DeckPreview(photoLoaded: false).preferredColorScheme(.dark) }
