import SwiftUI
import PhotosUI
import FilmEngine

struct EditorView: View {
    @State private var model = EditorModel()
    @State private var photo: PhotosPickerItem?
    @State private var isExporting = false
    @State private var showsPresets = false
    @State private var showsContactSheet = false

    var body: some View {
        EditorScreen(model: model, canvas: canvas, error: model.error, photo: $photo,
                     showPresets: { showsPresets = true }, showContactSheet: { showsContactSheet = true },
                     showExport: { isExporting = true })
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showsPresets) { PresetSheet(model: model) }
            .sheet(isPresented: $showsContactSheet) { ContactSheetView() }
            .sheet(isPresented: $isExporting) { ExportSheet(model: model) }
            .task { model.loadCatalogue() }
            .task { await model.watchThermalState() }
            .task(id: photo) {
                guard let photo else { return }
                await model.open(photo)
            }
    }

    private var canvas: CanvasView.Content {
        if model.isLoading { return .loading }
        if let pixels = model.pixels {
            return .photo(pixels: pixels, before: model.beforePixels, milliseconds: model.lastRenderMilliseconds)
        }
        // Decoding finishes before the first graded render is published.
        if model.beforePixels != nil && model.error == nil { return .loading }
        return .empty
    }
}

/// Shared by the running editor and the acceptance previews, so each state uses
/// exactly the same canvas allocation and fixed deck frame.
private struct EditorScreen: View {
    let model: EditorModel
    let canvas: CanvasView.Content
    var error: String?
    @Binding var photo: PhotosPickerItem?
    let showPresets: () -> Void
    let showContactSheet: () -> Void
    let showExport: () -> Void
    @State private var selection = EditorSelection()
    @State var isLoupeEnabled = false
    @State private var holdingBefore = false
    @State var accessibleBefore = false
    var previewReadout = false

    private var isComparing: Bool { canvas.hasPhoto && (holdingBefore || accessibleBefore) }

    var body: some View {
        VStack(spacing: 0) {
            CanvasView(content: canvas, isComparing: isComparing,
                       isLoupeEnabled: isLoupeEnabled,
                       parameter: selection.isFilmstripOpen ? nil : selection.activeParameter(in: model.parameters(for: selection.stage)),
                       onCompare: { holdingBefore = $0 }, previewReadout: previewReadout)
                .id(model.selectedStock)
                .accessibilityElement(children: canvas.hasPhoto ? .ignore : .combine)
                .accessibilityLabel(canvas.accessibilityLabel)
                .accessibilityValue(isComparing ? "Original" : "")
                .modifier(CanvasAccessibility(isEnabled: canvas.hasPhoto, showsOriginal: $accessibleBefore,
                                              isLoupeEnabled: $isLoupeEnabled))
            DeckView(model: model, selection: selection, hasPhoto: canvas.hasPhoto, photo: $photo,
                     isLoupeEnabled: $isLoupeEnabled, showPresets: showPresets,
                     showContactSheet: showContactSheet, showExport: showExport, error: error)
                .opacity(isComparing ? Tokens.Canvas.comparingDeckOpacity : 1)
        }
        // The deck's bottom gutter includes the home indicator, as in 1j. The
        // canvas surround extends behind the status area; the photo stays safe.
        .ignoresSafeArea(.container, edges: .bottom)
        .background(Tokens.Palette.canvas.ignoresSafeArea())
        .onChange(of: isComparing) { Haptics.compare() }
        .onChange(of: photo) { accessibleBefore = false; isLoupeEnabled = false; holdingBefore = false }
        .onChange(of: canvas.hasPhoto) { if !canvas.hasPhoto { accessibleBefore = false; isLoupeEnabled = false; holdingBefore = false } }
    }
}

private struct CanvasAccessibility: ViewModifier {
    let isEnabled: Bool
    @Binding var showsOriginal: Bool
    @Binding var isLoupeEnabled: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if isEnabled {
            content.accessibilityAction(named: showsOriginal ? "Show edited photo" : "Show original photo") {
                showsOriginal.toggle()
            }
            .accessibilityAction(named: isLoupeEnabled ? "Turn loupe off" : "Show 1:1 loupe") {
                isLoupeEnabled.toggle()
            }
            // SwiftUI caches custom action names on the accessibility element.
            // Refresh its identity only for the VoiceOver toggle, never a hold.
            .id("\(showsOriginal)-\(isLoupeEnabled)")
        } else {
            content
        }
    }
}

private struct EditorPreview: View {
    enum State { case graded, original, loupe, dragging, empty, loading, error }
    let state: State
    @SwiftUI.State private var model = EditorModel()
    @SwiftUI.State private var canvas: CanvasView.Content = .empty
    @SwiftUI.State private var previewError: String?

    var body: some View {
        EditorScreen(model: model, canvas: canvas, error: previewError, photo: .constant(nil),
                     showPresets: {}, showContactSheet: {}, showExport: {},
                     isLoupeEnabled: state == .loupe, accessibleBefore: state == .original,
                     previewReadout: state == .dragging)
            .task {
                switch state {
                case .empty: canvas = .empty
                case .loading: canvas = .loading
                case .error:
                    canvas = .empty
                    previewError = "The photo could not be loaded."
                case .graded, .original, .loupe, .dragging:
                    do {
                        model.loadCatalogue()
                        model.selectedStock = "portra-400"
                        let renderer = try Renderer()
                        let input = try ContactSheetReference.image()
                        let before = try await renderer.render(image: .linear(input), profile: .identity,
                                                               settings: ContactSheetReference.settings)
                        let pixels = try await renderer.render(image: .linear(input), profile: model.profile,
                                                               settings: ContactSheetReference.settings)
                        canvas = .photo(pixels: pixels, before: before, milliseconds: 18)
                    } catch { previewError = error.localizedDescription }
                }
            }
    }
}

#Preview("Editor · graded frame") { EditorPreview(state: .graded).preferredColorScheme(.dark) }
#Preview("Editor · held compare") { EditorPreview(state: .original).preferredColorScheme(.dark) }
#Preview("Editor · empty") { EditorPreview(state: .empty).preferredColorScheme(.dark) }
#Preview("Editor · loading") { EditorPreview(state: .loading).preferredColorScheme(.dark) }
#Preview("Editor · error") { EditorPreview(state: .error).preferredColorScheme(.dark) }
#Preview("Editor · empty · light surround") { EditorPreview(state: .empty).preferredColorScheme(.light) }

#Preview("Editor · 1:1 loupe") { EditorPreview(state: .loupe).preferredColorScheme(.dark) }

#Preview("Editor · fine drag") { EditorPreview(state: .dragging).preferredColorScheme(.dark) }
