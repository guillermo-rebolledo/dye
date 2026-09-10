import SwiftUI
import FilmEngine

/// Real output previews for the explicit Output browser.
struct OutputStageCards: View {
    let model: EditorModel
    var isEnabled = true
    @State private var thumbnails: [OutputStage: RenderedPixels] = [:]
    @State private var error: String?

    var body: some View {
        HStack(spacing: Tokens.Metrics.segmentRadius) {
            ForEach(model.outputStages, id: \.self) { stage in
                Button {
                    guard model.outputStage != stage else { return }
                    model.outputStage = stage
                    Haptics.step()
                } label: {
                    ZStack(alignment: .bottomLeading) {
                        if let pixels = thumbnails[stage] {
                            FilmCanvas(image: pixels)
                                .aspectRatio(CGFloat(pixels.width) / CGFloat(pixels.height), contentMode: .fill)
                                .frame(height: 86).clipped()
                        } else { DevelopingFrame(showsCaption: false) }
                        Text(stage.displayName).typeStyle(.chipName)
                            .foregroundStyle(Tokens.Palette.textPrimary)
                            .padding(8).background(.black.opacity(0.55), in: Capsule())

                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 86)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: Tokens.Metrics.chipRadius)
                        .strokeBorder(model.outputStage == stage ? Tokens.Discrete.cardAccent : .clear,
                                      lineWidth: Tokens.Discrete.cardRing))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(stage.displayName)
                .accessibilityValue(model.outputDescription(for: stage))
                .accessibilityAddTraits(model.outputStage == stage ? .isSelected : [])
            }
        }
        .frame(height: 86)
        .task(id: previewKey) {
            thumbnails = [:]
            error = nil
            do {
                for stage in model.outputStages {
                    let pixels = try await model.outputThumbnail(for: stage)
                    try Task.checkCancellation()
                    thumbnails[stage] = pixels
                }
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
        .overlay(alignment: .top) {
            if error != nil {
                Text("Preview unavailable").font(.caption2).foregroundStyle(Tokens.Palette.textPrimary)
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : Tokens.Deck.unavailableOpacity)
    }

    private var previewKey: PreviewKey {
        var settings = model.settings
        // Both pictures explicitly override output; selecting one does not
        // invalidate either preview or flash the cards back to placeholders.
        settings.outputStage = nil
        return PreviewKey(image: model.thumbnailGeneration, stock: model.selectedStock, settings: settings)
    }

    private struct PreviewKey: Equatable {
        let image: UUID
        let stock: String
        let settings: RenderSettings
    }
}

private struct OutputStagePreview: View {
    @State private var model = EditorModel()
    var body: some View {
        OutputStageCards(model: model).padding(Tokens.Metrics.space16)
            .background(Tokens.Palette.deck)
            .task { await model.loadCatalogue(); model.selectedStock = "portra-400"; model.outputStage = .print }
    }
}

#Preview("Scan and Print · Print selected") { OutputStagePreview().preferredColorScheme(.dark) }
