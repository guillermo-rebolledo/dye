import SwiftUI
import FilmEngine

/// The cards occupy the combined readout + track slot (34 + 28), as in screen 1f.
/// A 62 pt card cannot fit inside the track alone; the caption remains reserved.
struct OutputStageCards: View {
    let model: EditorModel
    var isEnabled = true

    var body: some View {
        HStack(spacing: Tokens.Metrics.segmentRadius) {
            ForEach(model.outputStages, id: \.self) { stage in
                Button {
                    guard model.outputStage != stage else { return }
                    model.outputStage = stage
                    Haptics.step()
                } label: {
                    VStack(alignment: .leading, spacing: Tokens.Metrics.space4) {
                        Text(stage.displayName).typeStyle(.chipName)
                            .foregroundStyle(Tokens.Palette.textPrimary)
                        Text(description(stage)).typeStyle(.caption)
                            .foregroundStyle(Tokens.Deck.captionInk)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Tokens.Metrics.space10)
                    .frame(height: Tokens.Discrete.cardHeight)
                    .modifier(DeckFace(selected: model.outputStage == stage && isEnabled))
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
        .frame(height: Tokens.Discrete.cardHeight)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : Tokens.Deck.unavailableOpacity)
    }

    private func description(_ stage: OutputStage) -> String {
        // The first sentence of the existing copy; the complete explanation is
        // available to VoiceOver and in the active control's caption.
        let copy = model.outputDescription(for: stage)
        guard let end = copy.firstIndex(of: ".") else { return copy }
        return String(copy[...end])
    }
}

private struct OutputStagePreview: View {
    @State private var model = EditorModel()
    var body: some View {
        OutputStageCards(model: model).padding(Tokens.Metrics.space16)
            .background(Tokens.Palette.deck)
            .task { model.loadCatalogue(); model.selectedStock = "portra-400"; model.outputStage = .print }
    }
}

#Preview("Scan and Print · Print selected") { OutputStagePreview().preferredColorScheme(.dark) }
