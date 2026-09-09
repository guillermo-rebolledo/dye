import SwiftUI

struct SettingsView: View {
    let model: EditorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        GlossaryView(model: model)
                    } label: {
                        Label("Glossary", systemImage: "book.closed")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Tokens.Palette.accent)
        .preferredColorScheme(.dark)
    }
}

/// Explanations live here so the editor can concentrate on the photograph.
struct GlossaryView: View {
    let model: EditorModel
    @State private var search = ""

    private var entries: [GlossaryEntry] {
        let context = EditorStage.allCases.flatMap { model.parameters(for: $0) }
        return GlossaryEntry.all.map { entry in
            guard let parameter = context.first(where: { $0.name == entry.title }),
                  let caption = parameter.captionText, !caption.isEmpty else { return entry }
            return GlossaryEntry(section: entry.section, title: entry.title,
                                 explanation: entry.explanation + "\n\nCurrent stock · " + model.profile.metadata.displayName + "\n" + caption)
        }
    }

    private var matches: [GlossaryEntry] {
        entries.filter { search.isEmpty || ($0.title + " " + $0.explanation).localizedStandardContains(search) }
    }

    var body: some View {
        List {
            ForEach(["Controls", "Light", "Film", "Lab", "Adjust", "Export"], id: \.self) { section in
                let items = matches.filter { $0.section == section }
                if !items.isEmpty {
                    Section(section) {
                        ForEach(items) { entry in
                            NavigationLink {
                                ScrollView {
                                    Text(entry.explanation)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding()
                                        .textSelection(.enabled)
                                }
                                .navigationTitle(entry.title)
                                .navigationBarTitleDisplayMode(.inline)
                            } label: {
                                Text(entry.title)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Glossary")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Find a control or term")
        .overlay {
            if matches.isEmpty { ContentUnavailableView.search(text: search) }
        }
    }
}

private struct GlossaryEntry: Identifiable {
    let section: String
    let title: String
    let explanation: String
    var id: String { title }

    static let all: [Self] = [
        .init(section: "Controls", title: "Dials", explanation: "Drag the scale beneath a value to adjust it. The fixed centre marker shows your setting. A detent is a gentle snap at a reference value, such as neutral exposure or the stock’s natural grain intensity. Touch and hold a parameter name, or double-tap it, to reset that control. VoiceOver users can swipe up or down to adjust a dial."),
        .init(section: "Controls", title: "Compare & fine adjustment", explanation: "Hold the photo to compare it with the original. Drag horizontally on the photo for finer adjustment of the active control. VoiceOver offers comparison and loupe actions on the photo."),
        .init(section: "Controls", title: "Loupe", explanation: "The loupe shows a 1:1 view for inspecting detail. Touch and hold the Contact Sheet button to turn it on or off."),
        .init(section: "Controls", title: "Presets", explanation: "Save a name for the current stock and editing settings. Apply a preset to reuse that look on another photo."),
        .init(section: "Controls", title: "Contact Sheet", explanation: "Compare the stocks using the same bundled reference image. This reference stays fixed so differences between stocks are easier to see."),
        .init(section: "Light", title: "Exposure", explanation: "Adjust the light reaching the simulated film, measured in stops. Positive values add light; negative values reduce it."),
        .init(section: "Light", title: "Temperature", explanation: "Set the colour temperature of the light in kelvin. The reference point follows the selected stock’s daylight or tungsten balance."),
        .init(section: "Light", title: "Tint", explanation: "Adjust the green–magenta balance. Zero is neutral."),
        .init(section: "Light", title: "Exposure time", explanation: "Simulate the film’s response to exposure duration. Some stocks change response during long exposures; this is called reciprocity failure. This control appears for stocks that model that behaviour."),
        .init(section: "Film", title: "Stock", explanation: "A stock defines the film’s colour response, contrast and texture. Available controls depend on the stock. Identity applies no film response. Some stocks approximate another emulsion; their appearance is a simulation."),
        .init(section: "Film", title: "Contrast filter", explanation: "Simulate coloured glass in front of black-and-white film. Filters change the relative brightness of colours. The app compensates for the filter’s light loss."),
        .init(section: "Film", title: "Development", explanation: "Change the simulated development of the film. Push and pull settings affect tone and contrast. Available ranges depend on the stock."),
        .init(section: "Film", title: "Bloom", explanation: "Spread bright light into a soft glow. 100% is the stock’s modelled strength; higher values exaggerate it."),
        .init(section: "Film", title: "Halation", explanation: "Simulate light spreading back through the film around bright edges. The colour and strength depend on the stock. 100% is its modelled strength."),
        .init(section: "Film", title: "Grain", explanation: "Control film texture. 100% uses the stock’s modelled intensity; zero removes it. When the device is hot, export may use a lighter grain model, shown in the export status."),
        .init(section: "Lab", title: "Output", explanation: "Scan interprets the negative as a scanned image. Print simulates the negative enlarged onto RA-4 paper. Reversal film is already a positive image and does not offer these choices."),
        .init(section: "Lab", title: "Vignette", explanation: "Darken the edges of the frame. Zero leaves the edges unchanged."),
        .init(section: "Lab", title: "Gate weave", explanation: "Add simulated film-gate displacement. Zero keeps the frame steady."),
        .init(section: "Lab", title: "Frame border", explanation: "Add a border around the image. Zero leaves it borderless."),
        .init(section: "Adjust", title: "Brilliance", explanation: "Brighten the shadows, tone down the highlights and add midtone contrast together, so detail stands out. Applies to the scan after the film, like a photo editor. Zero is off."),
        .init(section: "Adjust", title: "Highlights", explanation: "Adjust only the brightest parts of the photo. Negative values recover highlights at or past white; positive values push them up."),
        .init(section: "Adjust", title: "Shadows", explanation: "Adjust only the darkest parts of the photo. Positive values reveal shadow detail; negative values deepen it. Black stays black."),
        .init(section: "Adjust", title: "Contrast", explanation: "Increase or decrease the difference between light and dark areas about mid-grey. Black and white are held in place."),
        .init(section: "Adjust", title: "Brightness", explanation: "Shift the midtones while keeping black and white where they are. Unlike Exposure, this changes the scan rather than the light reaching the film."),
        .init(section: "Adjust", title: "Black point", explanation: "Set the darkest point of the image. Positive values deepen the blacks; negative values lift them to a matte grey."),
        .init(section: "Adjust", title: "Saturation", explanation: "Adjust the overall colour intensity. −100 is a neutral grey at the same brightness."),
        .init(section: "Adjust", title: "Vibrance", explanation: "Boost muted colours more than vivid ones while keeping skin tones natural. Negative values desaturate evenly."),
        .init(section: "Export", title: "Photo format", explanation: "HEIF and JPEG save eight bits per colour channel. TIFF saves sixteen bits per channel. Save to Photos renders the full-resolution image and adds it to your device’s photo library after permission is granted."),
        .init(section: "Export", title: "Colour space", explanation: "Display P3 preserves a wider range of colours. sRGB is useful for destinations that may discard colour profiles. Exported photos include a colour profile."),
        .init(section: "Export", title: "Photo date", explanation: "Today uses the current date. Original date uses the source photo’s date when available. If the source has no original date, the app uses today. A photo saved with an older date may appear earlier in a date-sorted library."),
        .init(section: "Export", title: "LUT", explanation: "A .cube LUT stores a colour mapping: the stock’s response, exposure, white balance, development and adjustments. It excludes spatial effects such as grain, halation, bloom, micro-contrast and vignette, so it will not reproduce the complete rendered photo. Use Share to save or send the LUT file.")
    ]
}
