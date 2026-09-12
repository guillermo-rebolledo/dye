import SwiftUI
import PhotosUI
import FilmEngine

/// Each tap is a new import, including choosing the same photograph again.
@MainActor final class PickedPhoto: Equatable {
    nonisolated let id = UUID()
    private let item: PhotosPickerItem

    init(item: PhotosPickerItem) { self.item = item }

    nonisolated static func == (lhs: PickedPhoto, rhs: PickedPhoto) -> Bool {
        lhs.id == rhs.id
    }

    /// The item's own representation, including RAW and its colour metadata, rather
    /// than a round trip through `UIImage`. What keeps the system from transcoding it
    /// on the way out is `preferredItemEncoding: .current` on the picker below.
    func loadData() async throws -> Data? {
        try await item.loadTransferable(type: Data.self)
    }
}

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
                selection = PickedPhoto(item: picked)
            }
    }
}
