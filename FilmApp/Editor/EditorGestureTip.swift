import SwiftUI

/// Dismissed once, explicitly. The same instructions remain in the Glossary.
struct EditorGestureTip: View {
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Metrics.space10) {
            Text("Hold the photo to compare. Drag across it for fine adjustments. Tap Reset to restore a changed control.")
                .font(.footnote)
                .foregroundStyle(Tokens.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss editing tips", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .frame(width: Tokens.Metrics.minimumHitTarget, height: Tokens.Metrics.minimumHitTarget)
                .foregroundStyle(Tokens.Palette.textPrimary)
        }
        .padding(.horizontal, Tokens.Metrics.space16)
        .padding(.vertical, Tokens.Metrics.space5)
        .background(Tokens.Palette.deck)
    }
}
