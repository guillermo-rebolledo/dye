import SwiftUI
import UIKit
import FilmEngine

struct EditorView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = EditorModel()
    @State private var photo: PickedPhoto?
    @State private var isExporting = false
    @State private var showsSettings = false
    @State private var showsPresets = false
    @State private var showsContactSheet = false

    var body: some View {
        NavigationStack {
            EditorScreen(model: model, canvas: canvas, error: model.error,
                         openAsSRGB: model.refusedPhoto == nil ? nil : { Task { await model.openRefusedPhotoAsSRGB() } }, photo: $photo,
                         showPresets: { showsPresets = true }, showContactSheet: { showsContactSheet = true },
                         showExport: { isExporting = true }, showSettings: { showsSettings = true })
                .toolbar(.hidden, for: .navigationBar)
        }
            .tint(Tokens.Palette.textPrimary)
            .preferredColorScheme(.dark)
            .overlay(alignment: .top) { ConfirmationToast(message: model.confirmation) }
            .sheet(isPresented: $showsSettings) { SettingsView(model: model) }
            .sheet(isPresented: $showsPresets) { PresetSheet(model: model).filmSheet() }
            .fullScreenCover(isPresented: $showsContactSheet) {
                ContactSheetView(selectedStock: model.selectedStock) { try await model.catalogueForContactSheet() }
            }
            .sheet(isPresented: $isExporting) { ExportSheet(model: model).filmSheet() }
            .task { await model.loadCatalogue() }
            .task { await model.refreshPhotoAccess() }
            // Granting access means leaving for Settings, so coming back is the only
            // signal the app gets that the answer may have changed.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await model.refreshPhotoAccess() }
            }
            .task { await model.watchThermalState() }
            .task { await model.watchMemoryPressure() }
            .task(id: photo) {
                guard let photo else { return }
                await model.open(photo)
                if !Task.isCancelled, model.error != nil { self.photo = nil }
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
/// exactly the same canvas allocation and adaptive deck layout.
private struct EditorScreen: View {
    let model: EditorModel
    let canvas: CanvasView.Content
    var error: UserFacingError?
    /// Offered only when the app can still open the photograph the decoder refused.
    var openAsSRGB: (() -> Void)?
    @Binding var photo: PickedPhoto?
    let showPresets: () -> Void
    let showContactSheet: () -> Void
    let showExport: () -> Void
    var showSettings: () -> Void = {}
    @State private var selection = EditorSelection()
    @State var isLoupeEnabled = false
    @State private var holdingBefore = false
    @State private var adjusting = false
    @State var accessibleBefore = false
    @AppStorage("hasDismissedEditingTips") private var hasDismissedEditingTips = false
    /// Not persisted: the answer can change in Settings between launches, and a
    /// notice the user waved away once should not be the reason they never see it
    /// again after coming back to the app still unable to save.
    @State private var hasDismissedAccessNotice = false
    var previewReadout = false

    private var isComparing: Bool { canvas.hasPhoto && (holdingBefore || accessibleBefore) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                if canvas.hasPhoto || model.beforePixels != nil {
                    EditorPickers(model: model, selection: selection, hasPhoto: canvas.hasPhoto)
                        .opacity(isComparing ? Tokens.Canvas.comparingDeckOpacity : 1)
                } else {
                    Spacer(minLength: 0)
                }
                Button("Settings", systemImage: "gearshape", action: showSettings)
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .modifier(EditorGlass())
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            if canvas.hasPhoto || model.beforePixels != nil {
                editor
            } else if model.photoAccess == .denied && !hasDismissedAccessNotice {
                // Before the first photo rather than over the editor: a refusal is
                // about where an Export lands, and taking the app away from someone
                // mid-edit over it would cost them more than the save is worth.
                PhotoAccessScreen { hasDismissedAccessNotice = true }
            } else {
                PhotoWelcomeScreen(photo: $photo, isLoading: isLoading, error: error, openAsSRGB: openAsSRGB)
            }
        }
        .background(Tokens.Palette.canvas.ignoresSafeArea())
        .onChange(of: isComparing) { Haptics.compare() }
        .onChange(of: photo) { accessibleBefore = false; isLoupeEnabled = false; holdingBefore = false }
        .onChange(of: canvas.hasPhoto) { if !canvas.hasPhoto { accessibleBefore = false; isLoupeEnabled = false; holdingBefore = false } }
    }

    private var isLoading: Bool {
        if case .loading = canvas { return true }
        return false
    }

    private var editor: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                if geometry.size.width > geometry.size.height {
                    HStack(spacing: 0) {
                        photoCanvas
                        ScrollView { controls.fixedSize(horizontal: false, vertical: true) }.frame(width: min(393, geometry.size.width * 0.46))
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .background(Tokens.Palette.deck)
                    }
                } else {
                    VStack(spacing: 0) {
                        photoCanvas
                        ViewThatFits(in: .vertical) {
                            controls.fixedSize(horizontal: false, vertical: true)
                            ScrollView {
                                controls.fixedSize(horizontal: false, vertical: true)
                            }
                            .scrollBounceBehavior(.basedOnSize)
                        }
                            .frame(maxWidth: 560)
                            .frame(maxHeight: geometry.size.height * 0.6, alignment: .bottom)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity).background(Tokens.Palette.deck)
                    }
                }
            }
        }
    }

    private var photoCanvas: some View {
        CanvasView(content: canvas, isComparing: isComparing,
                   isLoupeEnabled: isLoupeEnabled,
                   parameter: (selection.isFilmstripOpen || selection.isOutputBrowserOpen) ? nil : selection.activeParameter(in: model.dialParameters),
                   onCompare: { holdingBefore = $0 }, previewReadout: previewReadout, isAdjusting: adjusting,
                   selectedStock: model.selectedStock)
            .accessibilityElement(children: canvas.hasPhoto ? .ignore : .combine)
            .accessibilityLabel(canvas.accessibilityLabel)
            .accessibilityValue(isComparing ? "Original" : (isLoupeEnabled ? "Preview zoom" : ""))
            .accessibilityHint(isLoupeEnabled
                              ? "Magnified editing preview. Export at full resolution to judge fine grain and sharpness."
                              : "Hold to compare. Drag horizontally for fine adjustment. More actions are available.")
            .modifier(CanvasAccessibility(isEnabled: canvas.hasPhoto, showsOriginal: $accessibleBefore,
                                          isLoupeEnabled: $isLoupeEnabled))
    }

    private var controls: some View {
        VStack(spacing: 0) {
            if canvas.hasPhoto && !hasDismissedEditingTips {
                EditorGestureTip { hasDismissedEditingTips = true }
            }
            if canvas.hasPhoto && model.canUndoPresetApplication {
                PresetUndoBanner(model: model)
            }
            if let error {
                ScrollView {
                    ErrorStrip(error: error, openAsSRGB: openAsSRGB)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }.frame(maxHeight: 96)
            }
            DeckView(model: model, selection: selection, hasPhoto: canvas.hasPhoto, photo: $photo,
                     isLoupeEnabled: $isLoupeEnabled, showPresets: showPresets,
                     showContactSheet: showContactSheet, showExport: showExport,
                     onDragging: { adjusting = $0 })
                .opacity(isComparing ? Tokens.Canvas.comparingDeckOpacity : 1)
        }
    }

}

/// The first photo starts here; the editing deck appears once an image is ready.
private struct PhotoWelcomeScreen: View {
    @Binding var photo: PickedPhoto?
    let isLoading: Bool
    let error: UserFacingError?
    var openAsSRGB: (() -> Void)?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: Tokens.Metrics.space20) {
                    Image(systemName: "photo.badge.plus")
                        .font(.largeTitle)
                        .foregroundStyle(Tokens.Palette.accent)
                        .accessibilityHidden(true)

                    VStack(spacing: Tokens.Metrics.space10) {
                        Text("Start with a photo")
                            .font(.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text("Choose a picture to explore film stocks and make it your own.")
                            .font(.body)
                            .foregroundStyle(Tokens.Palette.inkOnCanvas(0.7))
                    }

                    if isLoading {
                        ProgressView("Loading photo…")
                            .tint(Tokens.Palette.accent)
                    } else {
                        SinglePhotoPicker(selection: $photo) {
                            Label("Select a photo", systemImage: "plus")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: Tokens.Metrics.minimumHitTarget)
                                .padding(.horizontal, Tokens.Metrics.space16)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Tokens.Palette.accent)
                        .foregroundStyle(Tokens.Palette.canvas)
                        .accessibilityHint("Opens your photo library")
                    }

                    if let error {
                        ErrorStrip(error: error, openAsSRGB: openAsSRGB)
                    }
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(Tokens.Palette.inkOnCanvas)
                .frame(maxWidth: Tokens.Welcome.contentWidth)
                .padding(Tokens.Metrics.space20)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
        }
    }
}

/// Add-only access refused, which the app cannot ask for twice: iOS answers the second
/// request with the first answer, so Settings is the only way back and saying so is the
/// whole job of this screen.
private struct PhotoAccessScreen: View {
    let dismiss: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: Tokens.Metrics.space20) {
                    Image(systemName: "lock.square")
                        .font(.largeTitle)
                        .foregroundStyle(Tokens.Palette.accent)
                        .accessibilityHidden(true)

                    VStack(spacing: Tokens.Metrics.space10) {
                        Text("Dye cannot save to Photos")
                            .font(.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text("Turn on Add Photos Only for Dye in Settings to save your edits to your photo library. You can keep editing and sharing without it.")
                            .font(.body)
                            .foregroundStyle(Tokens.Palette.inkOnCanvas(0.7))
                    }

                    if let settings = URL(string: UIApplication.openSettingsURLString) {
                        Link(destination: settings) {
                            Text("Open Settings")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: Tokens.Metrics.minimumHitTarget)
                                .padding(.horizontal, Tokens.Metrics.space16)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Tokens.Palette.accent)
                        .foregroundStyle(Tokens.Palette.canvas)
                    }
                    Button("Continue without saving", action: dismiss)
                        .font(.subheadline)
                        .frame(minHeight: Tokens.Metrics.minimumHitTarget)
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(Tokens.Palette.inkOnCanvas)
                .frame(maxWidth: Tokens.Welcome.contentWidth)
                .padding(Tokens.Metrics.space20)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
        }
    }
}

/// One line over the canvas, for the things that happen where the user is not looking.
/// A save to Photos leaves nothing on screen to see, so this is the seeing.
private struct ConfirmationToast: View {
    let message: String?

    var body: some View {
        Group {
            if let message {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Tokens.Palette.textPrimary)
                    .padding(.horizontal, Tokens.Metrics.space16)
                    .frame(minHeight: Tokens.Metrics.chipHeight)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Tokens.Palette.edgeHairline, lineWidth: Tokens.Elevation.hairlineWidth))
                    .padding(.top, Tokens.Metrics.space10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: message)
        .allowsHitTesting(false)
        // Nothing moves focus to a toast, so VoiceOver has to be told rather than
        // shown. This is the only announcement of the save that reaches it.
        .accessibilityHidden(true)
        .onChange(of: message) { _, new in
            guard let new else { return }
            AccessibilityNotification.Announcement(new).post()
        }
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
            .accessibilityAction(named: isLoupeEnabled ? "Turn preview zoom off" : "Show preview zoom") {
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
        EditorScreen(model: model, canvas: canvas, error: previewError.map { UserFacingError(FilmError.invalid($0), doing: .rendering) }, photo: .constant(nil),
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
                        await model.loadCatalogue()
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

#Preview("Editor · preview zoom") { EditorPreview(state: .loupe).preferredColorScheme(.dark) }

#Preview("Editor · fine drag") { EditorPreview(state: .dragging).preferredColorScheme(.dark) }

/// One failure, said once, with the engine's own words kept behind a disclosure and
/// a way forward offered when there is one.
private struct ErrorStrip: View {
    let error: UserFacingError
    var openAsSRGB: (() -> Void)?
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Metrics.space5) {
            Text(error.message)
                .typeStyle(.caption)
                .foregroundStyle(Tokens.Palette.destructive)
                .fixedSize(horizontal: false, vertical: true)
            if let openAsSRGB, error.photoProblem?.canOpenAsSRGB == true {
                Button("Open as sRGB", action: openAsSRGB)
                    .font(.footnote.weight(.semibold))
                    .frame(minHeight: Tokens.Metrics.minimumHitTarget)
                    .accessibilityHint("Opens the photo assuming standard colours, which may not be exactly right")
            }
            if let details = error.details {
                Button(showsDetails ? "Hide details" : "Details") { showsDetails.toggle() }
                    .font(.footnote)
                    .frame(minHeight: Tokens.Metrics.minimumHitTarget)
                if showsDetails {
                    Text(details)
                        .typeStyle(.caption)
                        .foregroundStyle(Tokens.Palette.textTertiary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .contain)
    }
}
