import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import FilmEngine

/// Each tap is a new import, including choosing the same photograph again.
@MainActor final class PickedPhoto: Equatable {
    nonisolated let id = UUID()
    private let provider: NSItemProvider

    init(provider: NSItemProvider) { self.provider = provider }

    nonisolated static func == (lhs: PickedPhoto, rhs: PickedPhoto) -> Bool {
        lhs.id == rhs.id
    }

    func loadData() async throws -> Data? {
        // Keep the provider's preferred image representation, including RAW and
        // its colour metadata, instead of round-tripping through UIImage.
        guard let type = provider.registeredTypeIdentifiers.first(where: {
            UTType($0)?.conforms(to: .image) == true
        }) else { throw FilmError.photo(.undecodable) }
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: data) }
            }
        }
    }
}

/// A fresh, single-selection picker with no retained selection checkmarks.
struct SinglePhotoPicker<Label: View>: View {
    @Binding var selection: PickedPhoto?
    @ViewBuilder let label: () -> Label
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: { label() }
            .sheet(isPresented: $isPresented) {
                PhotoPickerController { photo in
                    // Dismiss before loading bytes; iCloud downloads and decoding
                    // show progress in the editor instead of holding up the picker.
                    isPresented = false
                    if let photo { selection = photo }
                }
                .ignoresSafeArea()
            }
    }
}

private struct PhotoPickerController: UIViewControllerRepresentable {
    let onPick: (PickedPhoto?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.selection = .default
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (PickedPhoto?) -> Void

        init(onPick: @escaping (PickedPhoto?) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            onPick(results.first.map { PickedPhoto(provider: $0.itemProvider) })
        }
    }
}
