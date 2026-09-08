import SwiftUI
import FilmEngine

struct ContactSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var profiles: [Profile] = []
    @State private var images: [String: RenderedPixels] = [:]
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                Text("Fixed HDR reference · all Stocks · Seed 253")
                    .font(.caption).foregroundStyle(.secondary).padding()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 16) {
                    ForEach(profiles) { profile in
                        VStack {
                            if let image = images[profile.id] {
                                FilmCanvas(image: image).aspectRatio(1.5, contentMode: .fit)
                            } else { ProgressView().frame(height: 110) }
                            Text(profile.metadata.displayName).font(.caption)
                        }
                    }
                }.padding()
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Contact Sheet")
            .toolbar { Button("Done") { dismiss() } }
            .task {
                do {
                    profiles = try ProfileCatalogue.bundled().profiles
                    let renderer = try Renderer()
                    let input = try ContactSheetReference.image()
                    for profile in profiles {
                        try Task.checkCancellation()
                        images[profile.id] = try await renderer.render(image: .linear(input), profile: profile,
                                                                       settings: ContactSheetReference.settings)
                    }
                } catch is CancellationError { }
                catch { self.error = error.localizedDescription }
            }
        }
    }
}
