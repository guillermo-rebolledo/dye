import SwiftUI
import SwiftData
import FilmEngine

@Model final class Preset {
    var name: String
    var stockID: String
    var settingsData: Data
    var createdAt: Date

    init(name: String, stockID: String, settings: RenderSettings) throws {
        self.name = name
        self.stockID = stockID
        self.settingsData = try JSONEncoder().encode(settings)
        self.createdAt = Date()
    }
}

struct PresetSheet: View {
    let model: EditorModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Preset.createdAt, order: .reverse) private var presets: [Preset]
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Save current Stock and settings") {
                    TextField("Preset name", text: $name)
                    Button("Save Preset") {
                        do {
                            let preset = try Preset(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                                    stockID: model.selectedStock, settings: model.settings)
                            context.insert(preset)
                            do { try context.save() } catch { context.rollback(); throw error }
                            name = ""
                        } catch { self.error = error.localizedDescription }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section("Saved Presets") {
                    if presets.isEmpty { Text("Save a Preset to use it on your next photo.").foregroundStyle(.secondary) }
                    ForEach(presets) { preset in
                        Button(preset.name) {
                            do {
                                try model.applyPreset(stockID: preset.stockID,
                                                      settings: JSONDecoder().decode(RenderSettings.self, from: preset.settingsData))
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(presets[index]) }
                        do { try context.save() } catch { context.rollback(); self.error = error.localizedDescription }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Presets")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
