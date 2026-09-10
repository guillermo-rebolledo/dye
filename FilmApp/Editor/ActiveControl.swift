import SwiftUI

/// Readout and tape are separate slots: the rail owns selection between them.
struct ActiveControl: View {
    let parameter: Parameter?
    let model: EditorModel
    var isEnabled = true
    var showsTrack = false
    var onDragging: (Bool) -> Void = { _ in }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if showsTrack { track }
            else { readout }
        }
        .onChange(of: parameter?.value.wrappedValue) { old, new in
            guard !showsTrack, let parameter, let old, let new,
                  parameter.id == .temperature || parameter.id == .exposureTime,
                  let threshold = parameter.detent else { return }
            if (old < threshold && new >= threshold) || (old > threshold && new <= threshold) {
                Haptics.thresholdCrossing()
            }
        }
    }

    @ViewBuilder private var readout: some View {
        if let parameter {
            let parts = parameter.readoutParts
            let numeric = Double(parts.number) != nil
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if numeric {
                    Text(isEnabled ? parts.number : "—")
                        .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 28 : 32, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .frame(width: Tokens.Deck.readoutNumberWidth)
                        .contentTransition(reduceMotion ? .identity : .numericText(value: parameter.value.wrappedValue))
                        .animation(reduceMotion ? nil : .snappy(duration: 0.12), value: parameter.value.wrappedValue)
                } else {
                    Text(isEnabled ? parameter.readout : "—")
                        .font(.system(size: 22, weight: .medium, design: .monospaced))
                }
                if numeric && isEnabled && !parts.unit.isEmpty {
                    Text(parts.unit).font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(parameter.tag != nil ? Tokens.Palette.accent : Tokens.Deck.quietInk)
                }
            }
            .foregroundStyle(parameter.tag == .off ? Tokens.Deck.quietInk : Tokens.Palette.textPrimary)
            .lineLimit(1).minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(parameter.name)
            .accessibilityValue(isEnabled ? parameter.readout : "Unavailable")
            .overlay(alignment: .trailing) {
                if isEnabled, model.canBypass(parameter) {
                    Button { model.toggleBypass(parameter.id); Haptics.buttonPress() } label: {
                        Image(systemName: model.isBypassed(parameter.id) ? "circle" : "checkmark.circle.fill")
                            .foregroundStyle(Tokens.Palette.textPrimary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Apply \(parameter.name)")
                    .accessibilityValue(model.isBypassed(parameter.id) ? "Off" : "On")
                }
            }
        }
    }

    @ViewBuilder private var track: some View {
        if let parameter {
            switch parameter.control {
            case .dial, .shutterDial:
                ParameterDial(parameter: parameter, isEnabled: isEnabled, onDragging: onDragging)
            case .contrastFilterDiscs:
                ContrastFilterDiscs(parameter: parameter, filters: model.contrastFilters, isEnabled: isEnabled)
            case .filmstrip, .outputStageCards: Color.clear
            }
        }
    }
}
