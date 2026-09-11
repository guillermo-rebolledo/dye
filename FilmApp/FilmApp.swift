import SwiftUI
import SwiftData
import FilmEngine

@main
struct FilmApp: App {
    private let store = PresetStore.open()

    init() {
        // Whatever the last session left in the scratch directory is a full-resolution
        // copy of somebody's photograph, and this session has no use for it.
        ExportScratch.clear()
    }

    var body: some Scene {
        WindowGroup {
            EditorView()
                .environment(\.presetStoreOutcome, store.outcome)
        }
        .modelContainer(store.container)
    }
}

private struct PresetStoreOutcomeKey: EnvironmentKey {
    static let defaultValue = PresetStore.Outcome.onDisk
}

extension EnvironmentValues {
    /// Whether saved **Presets** are being kept on disk this session. The Presets
    /// sheet reads it so that "your presets are gone" is something the app says
    /// rather than something the user works out.
    var presetStoreOutcome: PresetStore.Outcome {
        get { self[PresetStoreOutcomeKey.self] }
        set { self[PresetStoreOutcomeKey.self] = newValue }
    }
}
