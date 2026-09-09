import SwiftUI
import UIKit

/// Every haptic the editor fires, named for what happened rather than for how it
/// feels, so a call site reads as the event and the feel stays consistent across
/// the app. The mapping is the handoff's table in §11.
///
/// **Reduce Motion removes animation only.** Nothing here consults it: a detent
/// under Reduce Motion still ticks, and a reset that no longer eases home still
/// says so through the Taptic Engine. Only the system's own haptics switch, which
/// UIKit honours for us, silences these.
@MainActor
enum Haptics {
    /// Arriving at a detent: 0 EV, the Stock Balance in Kelvin, 0 tint, the `box`
    /// Development Offset, 100 % on bloom, halation and grain, 0 on vignette,
    /// gate weave and frame border, the reciprocity threshold on the shutter dial.
    static func detent() { impact(.rigid) }

    /// One step of a discrete control.
    static func step() { selection() }

    /// Switching stage. Same feel as a step, because it is one.
    static func stageSwitch() { selection() }

    /// Switching which parameter the active control edits.
    static func parameterSwitch() { impact(.light) }

    /// Any button going down.
    static func buttonPress() { impact(.light) }

    /// Engaging or releasing hold-to-compare.
    static func compare() { impact(.light) }

    /// Crossing a threshold a caption describes — reciprocity, clipping, a
    /// Contrast Filter's stop cost.
    static func thresholdCrossing() { impact(.medium) }

    /// Loading a different Stock.
    static func stockChange() { impact(.medium) }

    /// Resetting a parameter to its default, by long press or double tap.
    static func reset() { impact(.rigid) }

    /// Running into the end of a range. Fires once on arrival, never repeatedly
    /// while a finger keeps pushing.
    static func rangeLimit() { impact(.heavy) }

    /// Warms the Taptic Engine for a gesture that is about to fire several of
    /// these. Call it when a drag begins, not on every change, and let it go
    /// cold again when the drag ends.
    static func prepare() {
        selectionGenerator.prepare()
        for style in warmStyles { generator(style).prepare() }
    }

    // MARK: Plumbing

    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]

    private static let warmStyles: [UIImpactFeedbackGenerator.FeedbackStyle] = [.light, .medium, .rigid, .heavy]

    private static func selection() {
        selectionGenerator.selectionChanged()
    }

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        generator(style).impactOccurred()
    }

    private static func generator(_ style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        if let existing = impactGenerators[style] { return existing }
        let generator = UIImpactFeedbackGenerator(style: style)
        impactGenerators[style] = generator
        return generator
    }
}

// MARK: - Preview

/// Fires each haptic on a real device. The preview canvas has no Taptic Engine,
/// so this one is worth running on hardware.
private struct HapticCatalogue: View {
    private let events: [(String, @MainActor () -> Void)] = [
        ("detent · rigid", Haptics.detent),
        ("step · selection", Haptics.step),
        ("stage switch · selection", Haptics.stageSwitch),
        ("parameter switch · light", Haptics.parameterSwitch),
        ("button press · light", Haptics.buttonPress),
        ("compare · light", Haptics.compare),
        ("threshold crossing · medium", Haptics.thresholdCrossing),
        ("stock change · medium", Haptics.stockChange),
        ("reset · rigid", Haptics.reset),
        ("range limit · heavy", Haptics.rangeLimit),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Metrics.space6) {
            ForEach(events, id: \.0) { name, fire in
                Button(action: fire) {
                    Text(name)
                        .typeStyle(.controlName)
                        .foregroundStyle(Tokens.Palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Tokens.Metrics.space14)
                        .frame(height: Tokens.Metrics.chipHeight)
                        .raisedSurface(cornerRadius: Tokens.Metrics.chipRadius)
                }
            }
        }
        .padding(Tokens.Metrics.space20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tokens.Palette.deck)
    }
}

#Preview("Haptics · dark") {
    HapticCatalogue().preferredColorScheme(.dark)
}

#Preview("Haptics · light") {
    HapticCatalogue().preferredColorScheme(.light)
}
