import SwiftUI

struct StageSelector: View {
    let selection: EditorSelection

    var body: some View {
        HStack(spacing: 0) {
            ForEach(EditorStage.allCases) { stage in
                if stage != .light {
                    Text("›").typeStyle(.controlName)
                        .foregroundStyle(Tokens.Palette.textDisabled)
                        .frame(width: Tokens.Metrics.space14)
                        .accessibilityHidden(true)
                }
                Button {
                    guard selection.stage != stage else { return }
                    // The raised face moves immediately; DeckView animates only
                    // the contents below the selector.
                    selection.select(stage)
                    Haptics.stageSwitch()
                } label: {
                    Text(stage.displayName)
                        .typeStyle(selection.stage == stage ? .stageName : .controlName)
                        .foregroundStyle(selection.stage == stage ? Tokens.Palette.textPrimary : Tokens.Palette.textTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: Tokens.Deck.segmentHeight)
                        .background {
                            if selection.stage == stage {
                                Color.clear.raisedSurface(cornerRadius: Tokens.Metrics.segmentRadius)
                            }
                        }
                        .frame(height: Tokens.Metrics.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection.stage == stage ? .isSelected : [])
            }
        }
        .padding(.horizontal, Tokens.Deck.segmentPadding)
        .frame(height: Tokens.Deck.selectorHeight)
        .recessedSurface(cornerRadius: Tokens.Metrics.troughRadius)
    }
}

private struct StageSelectorPreview: View {
    @State private var selection = EditorSelection()
    var body: some View {
        StageSelector(selection: selection).padding(Tokens.Metrics.space16).background(Tokens.Palette.deck)
    }
}

#Preview("Light › Film › Lab") { StageSelectorPreview().preferredColorScheme(.dark) }
