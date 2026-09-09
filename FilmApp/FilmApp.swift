import SwiftUI
import SwiftData
import FilmEngine

@main
struct FilmApp: App {
    var body: some Scene { WindowGroup { EditorView() }.modelContainer(for: Preset.self) }
}
