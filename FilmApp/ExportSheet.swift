import SwiftUI
import FilmEngine

/// The Export sheet: the full-resolution photo, or the colour half of the same look
/// as a `.cube`. Both come from the settings on screen, so what the sheet has to say
/// is not *what* it will render but what each of the two carries — which for the LUT
/// is only half of it.
struct ExportSheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Format", selection: $model.exportFormat) {
                        ForEach(ExportFormat.allCases) { format in Text(format.displayName).tag(format) }
                    }
                    Picker("Colour", selection: $model.exportOutput) {
                        Text("Display P3").tag(RenderSettings.Output.displayP3)
                        Text("sRGB").tag(RenderSettings.Output.sRGB)
                    }
                } header: {
                    Text("Photo")
                } footer: {
                    Text(photoFooter)
                }
                if model.isThrottled {
                    Section {
                        Label(thermalNote, systemImage: "thermometer.high")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button("Export photo") { model.exportImage() }
                        .disabled(!model.canExport)
                    Button("Export LUT (.cube)") { model.exportLUT() }
                        .disabled(!model.canExport)
                } footer: {
                    Text("A LUT is a colour mapping, one pixel at a time. This one carries the "
                         + "stock's response, your exposure, white balance and development, and nothing "
                         + "else: **no grain, no halation, no bloom, no micro-contrast and no vignette**, "
                         + "because none of those is a function of a single pixel's colour. It will look "
                         + "flatter than the app does, and that is the LUT being honest rather than wrong.")
                }
                if let export = model.export { status(export) }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { model.dismissExport(); dismiss() }.disabled(model.isExporting)
                }
            }
            .interactiveDismissDisabled(model.isExporting)
        }
    }

    @ViewBuilder private func status(_ export: EditorModel.Export) -> some View {
        switch export {
        case .running(let progress):
            Section {
                if progress.tileCount > 1 {
                    ProgressView(value: progress.fraction) {
                        Text("Rendering tile \(progress.completedTiles) of \(progress.tileCount)")
                    }
                    .accessibilityLabel("Export progress")
                    .accessibilityValue("\(Int(progress.fraction * 100)) percent")
                } else {
                    ProgressView("Rendering…")
                }
                Button("Cancel", role: .destructive) { model.cancelExport() }
            } footer: {
                Text("The frame is rendered a tile at a time so a 48MP photo fits in memory. "
                     + "You can keep editing while it runs.")
            }
        case .finished(let url):
            Section {
                ShareLink(item: url) { Label("Share \(url.lastPathComponent)", systemImage: "square.and.arrow.up") }
            }
        case .failed(let message):
            Section { Text(message).foregroundStyle(.red).font(.footnote) }
        }
    }

    private var photoFooter: String {
        let encoding = model.exportOutput == .sRGB
            ? "sRGB is the safe choice for anything that may strip the profile."
            : "Display P3 keeps the wider gamut the render works in; the file is tagged, so anything colour-managed will read it correctly."
        let depth = model.exportFormat == .tiff
            ? " TIFF is written at sixteen bits per channel."
            : " \(model.exportFormat.displayName) is written at eight bits per channel."
        return encoding + depth
    }

    private var thermalNote: String {
        "The device is running hot, so this export uses the \(model.exportGrainModel.rawValue) grain model "
        + "rather than \(model.profile.metadata.grain.model.rawValue). Continuing to ask for the expensive "
        + "one while the system is throttling would make the export slower and the phone hotter both."
    }
}
