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
    @State private var isLoupeEnabled = false
    @GestureState private var holdingBefore = false
    @State var accessibleBefore = false

    private var isComparing: Bool { canvas.hasPhoto && (holdingBefore || accessibleBefore) }

    var body: some View {
        VStack(spacing: 0) {
            CanvasView(content: canvas, isComparing: isComparing)
                .contentShape(Rectangle())
                .gesture(LongPressGesture(minimumDuration: Tokens.Canvas.compareHoldDuration)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .updating($holdingBefore) { value, state, _ in
                        if case .second(true, _) = value { state = true }
                    }, including: canvas.hasPhoto ? .all : .none)
                .accessibilityElement(children: canvas.hasPhoto ? .ignore : .combine)
                .accessibilityLabel(canvas.accessibilityLabel)
                .accessibilityValue(isComparing ? "Original" : "")
                .accessibilityActions {
                    if canvas.hasPhoto {
                        Button(accessibleBefore ? "Show edited photo" : "Show original photo") {
                            accessibleBefore.toggle()
                        }
                    }
                }
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
        .onChange(of: photo) { accessibleBefore = false }
        .onChange(of: canvas.hasPhoto) { if !canvas.hasPhoto { accessibleBefore = false } }
    }
}

private struct EditorPreview: View {
    enum State { case graded, original, empty, loading, error }
    let state: State
    @SwiftUI.State private var model = EditorModel()
    @SwiftUI.State private var canvas: CanvasView.Content = .empty
    @SwiftUI.State private var previewError: String?

    var body: some View {
        EditorScreen(model: model, canvas: canvas, error: previewError, photo: .constant(nil),
                     showPresets: {}, showContactSheet: {}, showExport: {}, accessibleBefore: state == .original)
            .task {
                switch state {
                case .empty: canvas = .empty
                case .loading: canvas = .loading
                case .error:
                    canvas = .empty
                    previewError = "The photo could not be loaded."
                case .graded, .original:
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
