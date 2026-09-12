import SwiftUI
import PhotosUI
import FilmEngine

/// A photograph the user chose, as the read that yields its bytes and an identity of
/// its own. Each tap is a new import, including choosing the same photograph again.
///
/// It holds the read rather than the thing being read from, so the only part of an
/// import the editor depends on is "something that yields the file's bytes".
/// `Scripts/check-preset-undo.py` runs the real `EditorModel` against the real engine
/// on macOS, and a `PhotosPickerItem` cannot be constructed to hand it; a closure can,
/// which is what lets that check exercise the import path rather than skip it.
@MainActor final class PickedPhoto: Equatable {
    nonisolated let id = UUID()
    private let read: () async throws -> Data?

    init(_ read: @escaping () async throws -> Data?) { self.read = read }

    nonisolated static func == (lhs: PickedPhoto, rhs: PickedPhoto) -> Bool {
        lhs.id == rhs.id
    }

    func loadData() async throws -> Data? { try await read() }
}

// MARK: - Picker

/// A single-selection picker, presented by the system rather than inside a sheet of
/// the app's own.
///
/// It used to be a `PHPickerViewController` wrapped in a `UIViewControllerRepresentable`
/// inside `.sheet`, which is a modal inside a modal: the grid's scrolling and the
/// app's sheet were both reading the same downward drag, and `.ignoresSafeArea()` —
/// there to hide the seam between the two — pushed the picker's own bottom bar under
/// the home indicator. `.photosPicker` is the same picker, presented the way the
/// system presents it, and the binding is a single optional item rather than a list,
/// so single selection is what the type says rather than what a limit enforces.
struct SinglePhotoPicker<Label: View>: View {
    @Binding var selection: PickedPhoto?
    @ViewBuilder let label: () -> Label
    @State private var isPresented = false
    @State private var item: PhotosPickerItem?

    var body: some View {
        Button { isPresented = true } label: { label() }
            .photosPicker(isPresented: $isPresented, selection: $item,
                          matching: .images, preferredItemEncoding: .current)
            .onChange(of: item) { _, picked in
                guard let picked else { return }
                // Cleared as it is taken, so choosing the same photograph a second
                // time is a change the binding reports rather than one it swallows.
                item = nil
                // The item's own representation, including RAW and its colour
                // metadata, rather than a round trip through `UIImage`. What keeps
                // the system from transcoding it is `preferredItemEncoding: .current`.
                selection = PickedPhoto { try await picked.loadTransferable(type: Data.self) }
            }
    }
}
