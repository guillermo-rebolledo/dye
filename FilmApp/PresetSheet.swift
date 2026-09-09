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

/// The Presets sheet: name the look on screen to keep it, and pick a saved one to
/// come back to it.
///
/// A row is a record of a saved look rather than a preview of the current one, so
/// its thumbnail renders at the Preset's own settings and its summary is read
/// straight out of them. The summary needs no render at all, which is what lets a
/// row be complete and readable before its thumbnail arrives — and lets a Preset
/// whose Stock has left the Catalogue still say what it was.
struct PresetSheet: View {
    let model: EditorModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Preset.createdAt, order: .reverse) private var presets: [Preset]
    @State private var name = ""
    @State private var error: String?

    private var rows: [PresetRow] {
        presets.map { PresetRow($0, catalogue: model.catalogueWithIdentity) }
    }

    var body: some View {
        let rows = rows
        SheetSurface(title: "Presets", done: { dismiss() }) {
            VStack(alignment: .leading, spacing: Tokens.Sheet.rowGap) {
                saveLine
                if let error {
                    Text(error).typeStyle(.caption).foregroundStyle(Tokens.Palette.destructive)
                }
                list(rows)
            }
            .padding(.bottom, Tokens.Metrics.space20)
        }
        .task(id: rows) { model.schedulePresetThumbnails(rows.compactMap(\.render)) }
    }

    // MARK: - Saving

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var saveLine: some View {
        HStack(spacing: Tokens.Sheet.labelGap) {
            TextField("Name this look", text: $name)
                .typeStyle(.sheetBody)
                .foregroundStyle(Tokens.Palette.textPrimary)
                .tint(Tokens.Palette.accent)
                .submitLabel(.done)
                .onSubmit(save)
                .padding(.horizontal, Tokens.Presets.fieldPadding)
                .frame(height: Tokens.Presets.fieldHeight)
                .recessedSurface(cornerRadius: Tokens.Presets.fieldRadius)
            Button("Save", action: save)
                .buttonStyle(SheetActionStyle(kind: .primary))
                .fixedSize()
                .frame(height: Tokens.Presets.fieldHeight)
                .disabled(trimmedName.isEmpty)
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        do {
            let preset = try Preset(name: trimmedName, stockID: model.selectedStock, settings: model.settings)
            context.insert(preset)
            do { try context.save() } catch { context.rollback(); throw error }
            name = ""
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    /// Named from the Stock and the Output Stage on screen, so it says what will
    /// actually be kept rather than describing Presets in general. It stops there:
    /// listing the parameters would name the same settings the clause after it has
    /// already promised to keep.
    // MARK: - Rows

    @ViewBuilder private func list(_ rows: [PresetRow]) -> some View {
        if rows.isEmpty {
            Text("No presets yet")
                .typeStyle(.caption)
                .foregroundStyle(Tokens.Palette.textQuaternary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Tokens.Metrics.space20)
        } else {
            List {
                ForEach(rows) { row in
                    Button { apply(row) } label: { PresetRowView(row: row, pixels: model.presetThumbnails[row.id]) }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Tokens.Sheet.rowSeparator)
                        // System red, not the accent. Destructive stays
                        // system-conventional so it is never read as "the film's
                        // own value", which is the one thing the accent means.
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) { delete(row.preset) }
                                .tint(Tokens.Palette.delete)
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .environment(\.defaultMinListRowHeight, Tokens.Presets.rowHeight)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Presets.listRadius, style: .continuous))
            .recessedSurface(cornerRadius: Tokens.Presets.listRadius)
        }
    }

    private func apply(_ row: PresetRow) {
        guard let settings = row.settings else {
            error = "This Preset could not be read"
            return
        }
        do {
            try model.applyPreset(stockID: row.preset.stockID, settings: settings)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func delete(_ preset: Preset) {
        context.delete(preset)
        do { try context.save() } catch let failure { context.rollback(); error = failure.localizedDescription }
    }
}

// MARK: - A row's contents

/// Everything a row can say without a render: the Preset, the settings it decoded
/// to, and the Stock it names when the Catalogue still has one.
struct PresetRow: Identifiable, Equatable {
    let preset: Preset
    let settings: RenderSettings?
    let profile: Profile?
    var id: PersistentIdentifier { preset.persistentModelID }

    init(_ preset: Preset, catalogue: [Profile]) {
        self.preset = preset
        settings = try? JSONDecoder().decode(RenderSettings.self, from: preset.settingsData)
        profile = ([.identity] + catalogue).first { $0.id == preset.stockID }
    }

    var render: EditorModel.PresetRender? {
        guard let settings else { return nil }
        return EditorModel.PresetRender(id: id, stockID: preset.stockID, settings: settings)
    }

    /// `Portra 400 · +0.3 EV · 5200 K · Print`, from the decoded settings alone.
    var summary: String {
        guard let settings else { return "Saved before this version; cannot be read" }
        return Self.look(profile, settings: settings, fallbackStockName: preset.stockID)
    }

    /// The error the row shows beside its summary when its Stock has gone. These are
    /// the words `applyPreset` throws, not a copy of them.
    var unavailable: String? { profile == nil ? EditorModel.stockUnavailable : nil }

    static func == (lhs: PresetRow, rhs: PresetRow) -> Bool {
        lhs.id == rhs.id && lhs.settings == rhs.settings && lhs.preset.name == rhs.preset.name
            && lhs.profile?.id == rhs.profile?.id
    }

    /// A Stock and the settings that differ from a fresh editor's, in the order the
    /// pipeline applies them. Everything at its default is left unsaid, because a
    /// line that names every parameter names nothing.
    static func look(_ profile: Profile?, settings: RenderSettings, fallbackStockName: String? = nil) -> String {
        let defaults = RenderSettings()
        var parts = [profile?.metadata.displayName ?? fallbackStockName ?? "Unknown stock"]
        if abs(settings.exposureStops - defaults.exposureStops) > 0.001 {
            parts.append(String(format: "%+.1f EV", settings.exposureStops))
        }
        if abs(settings.temperatureKelvin - defaults.temperatureKelvin) > 1 {
            parts.append(String(format: "%.0f K", settings.temperatureKelvin))
        }
        if settings.contrastFilter != .none { parts.append(settings.contrastFilter.rawValue) }
        if abs(settings.developmentOffset) > 0.05 {
            parts.append(String(format: "%@ %+.1f", settings.developmentOffset > 0 ? "push" : "pull",
                                settings.developmentOffset))
        }
        if settings.outputStage == OutputStage.print { parts.append(OutputStage.print.displayName) }
        return parts.joined(separator: " · ")
    }
}

private struct PresetRowView: View {
    let row: PresetRow
    let pixels: RenderedPixels?

    var body: some View {
        HStack(spacing: Tokens.Presets.rowGap) {
            thumbnail
            VStack(alignment: .leading, spacing: Tokens.Presets.nameGap) {
                Text(row.preset.name).typeStyle(.presetName).foregroundStyle(Tokens.Palette.textPrimary)
                    .lineLimit(1).truncationMode(.tail)
                Text(row.summary).typeStyle(.presetSummary).foregroundStyle(Tokens.Palette.textTertiary)
                    .lineLimit(1).truncationMode(.tail)
                if let unavailable = row.unavailable {
                    Text(unavailable).typeStyle(.presetSummary).foregroundStyle(Tokens.Palette.destructive)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Tokens.Presets.rowPadding)
        .frame(minHeight: Tokens.Presets.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(pixels == nil ? "developing" : "")
    }

    private var thumbnail: some View {
        Group {
            if let pixels {
                FilmCanvas(image: pixels)
                    .aspectRatio(CGFloat(pixels.width) / CGFloat(pixels.height), contentMode: .fill)
                    .frame(width: Tokens.Presets.thumbnailWidth, height: Tokens.Presets.thumbnailHeight)
                    .clipped()
            } else {
                DevelopingFrame(showsCaption: false)
            }
        }
        .frame(width: Tokens.Presets.thumbnailWidth, height: Tokens.Presets.thumbnailHeight)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Presets.thumbnailRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Presets.thumbnailRadius, style: .continuous)
            .strokeBorder(Tokens.Sheet.frameEdge, lineWidth: Tokens.Elevation.hairlineWidth))
    }
}

// MARK: - Preview

/// Real Presets in an in-memory store, with no photo loaded, so every row renders
/// against the Contact Sheet Reference exactly as the sheet does on a cold start.
/// One Preset names a Stock that is not in the Catalogue.
private struct PresetSheetPreview: View {
    let empty: Bool
    @SwiftUI.State private var model = EditorModel()
    private let container = try! ModelContainer(for: Preset.self,
                                                configurations: ModelConfiguration(isStoredInMemoryOnly: true))

    var body: some View {
        Tokens.Palette.canvas
            .ignoresSafeArea()
            .sheet(isPresented: .constant(true)) {
                PresetSheet(model: model).filmSheet().modelContainer(container)
            }
            .task {
                model.loadCatalogue()
                model.selectedStock = "portra-400"
                model.settings.outputStage = .print
                model.settings.exposureStops = 0.3
                model.settings.temperatureKelvin = 5200
                guard !empty else { return }
                for preset in Self.samples() { container.mainContext.insert(preset) }
            }
    }

    private static func samples() -> [Preset] {
        var warm = RenderSettings(temperatureKelvin: 5200, exposureStops: 0.3)
        warm.outputStage = .print
        let red = RenderSettings(developmentOffset: -1, contrastFilter: .red)
        return [(try? Preset(name: "Sunday portraits", stockID: "portra-400", settings: warm)),
                (try? Preset(name: "Slide, punchy", stockID: "velvia-50", settings: RenderSettings())),
                (try? Preset(name: "Old test — T-Max", stockID: "t-max-100", settings: red)),
                (try? Preset(name: "From a stock that left", stockID: "kodachrome-64", settings: RenderSettings()))]
            .compactMap { $0 }
    }
}

#Preview("Presets · rows, developing and a missing Stock") {
    PresetSheetPreview(empty: false).preferredColorScheme(.dark)
}

#Preview("Presets · empty") {
    PresetSheetPreview(empty: true).preferredColorScheme(.dark)
}
