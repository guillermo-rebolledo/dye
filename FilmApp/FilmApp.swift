import SwiftUI
import PhotosUI
import FilmEngine

@main
struct FilmApp: App {
    var body: some Scene { WindowGroup { EditorView() } }
}

struct EditorView: View {
    @State private var selection: PhotosPickerItem?
    @State private var pixels: RenderedPixels?
    @State private var error: String?
    @State private var isRendering = false
    @State private var renderer: Renderer?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let pixels {
                    FilmCanvas(image: pixels)
                        .aspectRatio(CGFloat(pixels.width) / CGFloat(pixels.height), contentMode: .fit)
                        .accessibilityLabel("Rendered photo")
                } else {
                    ContentUnavailableView("Open a photo", systemImage: "photo", description: Text("Choose a photo to begin."))
                }
                if isRendering { ProgressView("Rendering…") }
                if let error { Text(error).foregroundStyle(.red).accessibilityLabel("Error: \(error)") }
                PhotosPicker("Choose photo", selection: $selection, matching: .images, preferredItemEncoding: .current)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Dye")
            .task(id: selection) {
                guard let selection else { return }
                isRendering = true
                defer { isRendering = false }
                do {
                    error = nil
                    if renderer == nil { renderer = try Renderer() }
                    guard let data = try await selection.loadTransferable(type: Data.self), let renderer else {
                        throw FilmError.invalid("The photo could not be loaded")
                    }
                    let result = try await renderer.render(image: .encoded(data), profile: .identity)
                    try Task.checkCancellation()
                    pixels = result
                } catch is CancellationError { }
                catch { self.error = error.localizedDescription }
            }
        }
    }
}
