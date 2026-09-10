import SwiftUI
import FilmEngine

/// The Export sheet: the full-resolution photo, or the colour half of the same look
/// as a `.cube`. Both come from the settings on screen, so what the sheet has to say
/// is not *what* it will render but what each of the two carries — which for the LUT
/// is only half of it.
///
/// Shows rendering progress, the Photos save, and the confirmed result. It stays detented at 500 pt so the photo is still
/// visible above, and the export keeps running if it is dismissed.
struct ExportSheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    /// The frame the export was launched from. Editing continues behind the sheet, so
    /// the preview on screen when the record appears may no longer be the file — this
    /// is the one that is.
    @State private var launchedFrom: RenderedPixels?

    var body: some View {
        SheetSurface(title: "Export", isDoneEnabled: !model.isExporting, done: { model.dismissExport(); dismiss() }) {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Sheet.sectionGap) {
                    switch model.export {
                    case .running(let progress)?:
                        if model.isThrottled { ThermalNotice(model: model) }
                        lockedChoices
                        ExportTileGrid(progress: progress)
                        Button("Cancel") { model.cancelExport() }
                            .buttonStyle(SheetActionStyle(kind: .destructive))
                    case .saving?:
                        ProgressView("Saving to Photos…")
                            .foregroundStyle(Tokens.Palette.textSecondary)
                    case .finished(let record)?:
                        ExportFinished(record: record, thumbnail: launchedFrom) { model.dismissExport() }
                    case .failed(let message)?:
                        choices
                        Text(message).typeStyle(.caption).foregroundStyle(Tokens.Palette.destructive)
                        actions
                    case nil:
                        choices
                        actions
                    }
                }
                .padding(.bottom, Tokens.Metrics.space20)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .interactiveDismissDisabled(model.isExporting)
    }

    // MARK: - Idle

    private var choices: some View {
        VStack(alignment: .leading, spacing: Tokens.Sheet.sectionGap) {
            VStack(alignment: .leading, spacing: Tokens.Sheet.labelGap) {
                SheetSectionLabel("Format")
                SheetSegmented(label: "Format",
                               segments: ExportFormat.allCases.map { SheetSegment($0, formatName($0)) },
                               selection: $model.exportFormat)
            }
            VStack(alignment: .leading, spacing: Tokens.Sheet.labelGap) {
                SheetSectionLabel("Colour")
                SheetSegmented(label: "Colour",
                               segments: [SheetSegment(RenderSettings.Output.displayP3, "Display P3"),
                                          SheetSegment(RenderSettings.Output.sRGB, "sRGB")],
                               selection: $model.exportOutput)
            }
            VStack(alignment: .leading, spacing: Tokens.Sheet.labelGap) {
                SheetSectionLabel("Photo date")
                SheetSegmented(label: "Photo date",
                               segments: ExportDate.allCases.map { SheetSegment($0, $0.displayName) },
                               selection: $model.exportDate)
                if model.exportDate == .original {
                    Text(dateFooter).typeStyle(.caption).foregroundStyle(Tokens.Palette.textTertiary)
                }
            }
        }
    }

    private var dateFooter: String {
        guard model.exportDate == .original else { return "Saves to Photos with today’s date." }
        guard let date = model.originalDate else { return "No original date · Using today" }
        return "\(date.formatted(date: .abbreviated, time: .omitted))"
    }

    /// While the render runs, choices collapse to what they were fixed at.
    /// Changing them now would describe a file the renderer is not writing.
    private var lockedChoices: some View {
        VStack(alignment: .leading, spacing: Tokens.Sheet.labelGap) {
            SheetSectionLabel("Format · Colour")
            HStack(spacing: Tokens.Sheet.labelGap) {
                lockedValue(formatName(model.exportFormat))
                lockedValue(model.exportOutput.displayName)
            }
            Text("Photo date · \(model.exportDate.displayName)")
                .typeStyle(.caption).foregroundStyle(Tokens.Palette.textSecondary)
        }
        .opacity(Tokens.Sheet.lockedOpacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Format \(formatName(model.exportFormat)), colour \(model.exportOutput.displayName), photo date \(model.exportDate.displayName), locked while rendering")
    }

    private func lockedValue(_ name: String) -> some View {
        Text(name)
            .typeStyle(.stageName)
            .foregroundStyle(Tokens.Palette.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: Tokens.Sheet.segmentedHeight)
            .recessedSurface(cornerRadius: Tokens.Sheet.segmentedRadius)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: Tokens.Metrics.space10) {
            Button("Save to Photos") { launchedFrom = model.pixels; model.exportImage() }
                .buttonStyle(SheetActionStyle(kind: .primary))
                .disabled(!model.canExport)
            // A LUT is a mapping rather than a frame, so its record has no thumbnail.
            Button("Export LUT (.cube)") { launchedFrom = nil; model.exportLUT() }
                .buttonStyle(SheetActionStyle(kind: .standard))
                .disabled(!model.canExport)
            Text("Colour only").typeStyle(.caption).foregroundStyle(Tokens.Palette.textTertiary)
        }
    }

    private func formatName(_ format: ExportFormat) -> String {
        format == .tiff ? "16-bit TIFF" : format.displayName
    }


}

// MARK: - Rendering

/// A compact progress indicator backed by completed render tiles.
struct ExportTileGrid: View {
    let progress: ExportProgress

    var body: some View {
        Group {
            if progress.tileCount > 0 {
                ProgressView(value: Double(progress.completedTiles), total: Double(progress.tileCount)) {
                    Text("Rendering")
                }
            } else {
                ProgressView("Preparing…")
            }
        }
        .tint(Tokens.Palette.accent)
        .foregroundStyle(Tokens.Palette.textSecondary)
        .padding(.vertical, Tokens.Metrics.space10)
    }
}

// MARK: - Throttled

/// Information, not error. The amber dot means "the engine chose for you", which is
/// the same sense the accent carries everywhere else in the app — so no thermometer
/// and no yellow.
private struct ThermalNotice: View {
    let model: EditorModel

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Sheet.noticeGap) {
            Circle()
                .fill(Tokens.Palette.accent)
                .frame(width: Tokens.Sheet.noticeDot, height: Tokens.Sheet.noticeDot)
                .shadow(color: Tokens.Palette.accent, radius: Tokens.Sheet.noticeDotGlow)
                .padding(.top, Tokens.Metrics.space4)
                .accessibilityHidden(true)
            note.typeStyle(.notice).foregroundStyle(Tokens.Palette.textSecondary)
        }
        .padding(.vertical, Tokens.Sheet.noticePaddingVertical)
        .padding(.horizontal, Tokens.Sheet.noticePaddingHorizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Tokens.Sheet.noticeRadius, style: .continuous)
            .fill(Tokens.Palette.chip))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Sheet.noticeRadius, style: .continuous)
            .strokeBorder(Tokens.Palette.edgeHairline, lineWidth: Tokens.Elevation.hairlineWidth))
        .accessibilityElement(children: .combine)
    }

    /// The two grain models are named in mono, because they are identifiers rather
    /// than prose.
    private var note: Text {
        Text("Device warm · Using \(model.exportGrainModel.rawValue) grain")
    }
}

// MARK: - Finished

/// The file as a record: what was produced, at what size, in how many Tiles and how
/// long. All mono, because all of it is measurement.
private struct ExportFinished: View {
    let record: EditorModel.ExportRecord
    let thumbnail: RenderedPixels?
    let exportAnother: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Metrics.space10) {
            HStack(spacing: Tokens.Sheet.cardGap) {
                if let thumbnail {
                    FilmCanvas(image: thumbnail)
                        .aspectRatio(CGFloat(thumbnail.width) / CGFloat(thumbnail.height), contentMode: .fill)
                        .frame(width: Tokens.Export.thumbnailWidth, height: Tokens.Export.thumbnailHeight)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.Export.thumbnailRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Tokens.Export.thumbnailRadius, style: .continuous)
                            .strokeBorder(Tokens.Sheet.frameEdge, lineWidth: Tokens.Elevation.hairlineWidth))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: Tokens.Export.recordGap) {
                    Text(record.url.lastPathComponent)
                        .typeStyle(.recordName).foregroundStyle(Tokens.Palette.textPrimary)
                        .lineLimit(1).truncationMode(.middle)
                    ForEach(lines, id: \.self) { line in
                        Text(line).typeStyle(.recordDetail).foregroundStyle(Tokens.Palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
            }
            .sheetCard(padding: Tokens.Sheet.cardGap)
            .accessibilityElement(children: .combine)
            if let date = record.savedDate {
                Text("Saved to Photos · \(date.formatted(date: .abbreviated, time: .omitted))")
                    .typeStyle(.caption).foregroundStyle(Tokens.Palette.textSecondary)
            }
            ShareLink(item: record.url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(SheetActionStyle(kind: .primary))
            Button("Export another", action: exportAnother)
                .buttonStyle(SheetActionStyle(kind: .quiet))
        }
    }

    /// The raster line is absent for a LUT, which has no pixels and no gamut.
    private var lines: [String] {
        var parts: [String] = []
        if let width = record.pixelWidth, let height = record.pixelHeight, let megapixels = record.megapixels {
            // 8064 × 6048 is 48.8 MP and reads as 48: a megapixel count is what the
            // sensor is sold as, and rounding it up claims pixels that are not there.
            parts += ["\(width) × \(height)", "\(Int(megapixels)) MP"]
        }
        if let output = record.output { parts.append(output.displayName) }
        parts.append(size)
        return [parts.joined(separator: " · ")]
    }

    private var size: String {
        let megabytes = Double(record.byteCount) / 1e6
        return megabytes < 1 ? String(format: "%.0f kB", Double(record.byteCount) / 1e3)
                             : String(format: "%.1f MB", megabytes)
    }
}

// MARK: - Preview

/// Each state driven straight from `EditorModel.Export`, so the preview shows the
/// real cases rather than a mocked-up copy of them.
private struct ExportSheetPreview: View {
    enum State { case idle, rendering, throttled, finished, lut }
    let state: State
    @SwiftUI.State private var model = EditorModel()
    @SwiftUI.State private var pixels: RenderedPixels?

    var body: some View {
        VStack(spacing: 0) {
            if let pixels {
                FilmCanvas(image: pixels).aspectRatio(Tokens.Canvas.gateAspectRatio, contentMode: .fit)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Tokens.Palette.canvas)
        .task {
            await model.loadCatalogue()
            model.selectedStock = "portra-400"
            pixels = try? await Renderer().render(image: .linear(try ContactSheetReference.image()),
                                                  profile: model.profile, settings: ContactSheetReference.settings)
        }
        .sheet(isPresented: .constant(true)) {
            ExportSheetStates(state: state, model: model, thumbnail: pixels).filmSheet()
        }
    }
}

/// The states the model cannot be driven into from a preview — a live render, a hot
/// device — are rendered from their own values, using the same views the sheet uses.
private struct ExportSheetStates: View {
    let state: ExportSheetPreview.State
    let model: EditorModel
    let thumbnail: RenderedPixels?

    var body: some View {
        switch state {
        case .idle:
            ExportSheet(model: model)
        case .rendering:
            SheetSurface(title: "Export", isDoneEnabled: false, done: {}) {
                VStack(alignment: .leading, spacing: Tokens.Sheet.sectionGap) {
                    ExportTileGrid(progress: ExportProgress(completedTiles: 7, tileCount: 24))
                    Button("Cancel") {}.buttonStyle(SheetActionStyle(kind: .destructive))
                }
            }
        case .throttled:
            SheetSurface(title: "Export", isDoneEnabled: false, done: {}) {
                VStack(alignment: .leading, spacing: Tokens.Sheet.sectionGap) {
                    ThermalNotice(model: model)
                    ExportTileGrid(progress: ExportProgress(completedTiles: 3, tileCount: 9))
                    Button("Cancel") {}.buttonStyle(SheetActionStyle(kind: .destructive))
                }
            }
        case .finished:
            SheetSurface(title: "Export", done: {}) {
                ExportFinished(record: Self.photo, thumbnail: thumbnail, exportAnother: {})
            }
        case .lut:
            SheetSurface(title: "Export", done: {}) {
                ExportFinished(record: Self.lut, thumbnail: nil, exportAnother: {})
            }
        }
    }

    private static let photo = EditorModel.ExportRecord(
        url: URL(fileURLWithPath: "/tmp/portra-400.heic"), pixelWidth: 8064, pixelHeight: 6048,
        output: .displayP3, byteCount: 31_200_000, tileCount: 24, elapsedSeconds: 14.8)

    private static let lut = EditorModel.ExportRecord(
        url: URL(fileURLWithPath: "/tmp/portra-400.cube"), byteCount: 1_180_000,
        tileCount: 1, elapsedSeconds: 0.4)
}

#Preview("Export · idle") { ExportSheetPreview(state: .idle).preferredColorScheme(.dark) }
#Preview("Export · rendering") { ExportSheetPreview(state: .rendering).preferredColorScheme(.dark) }
#Preview("Export · throttled") { ExportSheetPreview(state: .throttled).preferredColorScheme(.dark) }
#Preview("Export · finished") { ExportSheetPreview(state: .finished).preferredColorScheme(.dark) }
#Preview("Export · finished LUT") { ExportSheetPreview(state: .lut).preferredColorScheme(.dark) }
