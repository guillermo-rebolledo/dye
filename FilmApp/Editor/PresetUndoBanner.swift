import SwiftUI

struct PresetUndoBanner: View {
    let model: EditorModel

    var body: some View {
        HStack(spacing: 12) {
            Text("Preset applied")
                .font(.footnote)
                .foregroundStyle(Tokens.Palette.textSecondary)
            Spacer(minLength: 0)
            Button("Undo preset", systemImage: "arrow.uturn.backward", action: model.undoPresetApplication)
                .font(.footnote.weight(.semibold))
                .frame(minHeight: Tokens.Metrics.minimumHitTarget)
                .accessibilityHint("Restores the stock and adjustments from before this preset")
        }
        .padding(.horizontal, Tokens.Metrics.space16)
        .foregroundStyle(Tokens.Palette.textPrimary)
        .background(Tokens.Palette.deck)
    }
}
