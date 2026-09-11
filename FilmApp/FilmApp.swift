import SwiftUI
import SwiftData
import FilmEngine

@main
struct FilmApp: App {
    init() {
        // Exports written by a version that never deleted them. The engine owns an
        // exported file's lifetime now, so this only has to repair the past — but a
        // full-resolution copy of a photograph should not survive an upgrade.
        Task.detached(priority: .utility) { ExportedFile.sweepLeftovers() }
    }

    var body: some Scene { WindowGroup { EditorView() }.modelContainer(for: Preset.self) }
}
