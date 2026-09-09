import SwiftUI

struct ActiveControl: View {
    let parameter: Parameter?
    let model: EditorModel
    var isEnabled = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header.frame(height: Tokens.Deck.headerHeight)
            Color.clear.frame(height: Tokens.Deck.headerGap)
            Group {
                if let parameter, parameter.control == .outputStageCards {
                    OutputStageCards(model: model, isEnabled: isEnabled)
                } else {
                    VStack(spacing: 0) {
                        readout.frame(height: Tokens.Deck.readoutHeight)
                        track.frame(height: Tokens.Track.height)
                    }
                }
            }
            .id(parameter?.id)
            .transition(.opacity)
            .animation(Tokens.Motion.ease(Tokens.Motion.parameterSwitch, reduceMotion: reduceMotion), value: parameter?.id)
        }
        .frame(height: Tokens.Deck.controlHeight + Tokens.Deck.extraHeight(for: dynamicTypeSize))
        .onChange(of: parameter?.id) {
            Haptics.parameterSwitch()
        }
        .onChange(of: observedValue) { previous, current in
            guard previous.id == current.id, isEnabled, let parameter,
                  let old = previous.value, let new = current.value,
                  parameter.id == .temperature || parameter.id == .exposureTime,
                  let threshold = parameter.detent else { return }
            let crossed: Bool
            if parameter.id == .exposureTime {
                crossed = (old > threshold) != (new > threshold)
            } else {
                func side(_ value: Double) -> Int { value == threshold ? 0 : value < threshold ? -1 : 1 }
                crossed = side(old) != side(new)
            }
            if crossed { Haptics.thresholdCrossing() }
        }
    }

    private struct ObservedValue: Equatable {
        let id: Parameter.Identity?
        let value: Double?
    }

    private var observedValue: ObservedValue {
        ObservedValue(id: parameter?.id, value: parameter?.value.wrappedValue)
    }

    private var header: some View {
        HStack(spacing: Tokens.Metrics.space5) {
            Text(parameter?.name ?? "").typeStyle(.controlName)
                .foregroundStyle(Tokens.Palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if isEnabled, parameter?.tag == .off {
                Text("OFF").typeStyle(.tag)
                    .foregroundStyle(Tokens.Palette.accent)
            }
        }
    }

    @ViewBuilder private var readout: some View {
        if let parameter {
            let parts = parameter.readoutParts
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Metrics.space6) {
                Text(isEnabled ? parts.number : "—")
                    .typeStyle(dynamicTypeSize.isAccessibilitySize ? .accessibleReadout : .readout)
                    .contentTransition(reduceMotion ? .identity : .numericText(value: parameter.value.wrappedValue))
                    .foregroundStyle(parameter.tag == .off ? Tokens.Deck.quietInk : Tokens.Palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(width: parts.unit.isEmpty || parameter.id == .contrastFilter ? nil : Tokens.Deck.readoutNumberWidth,
                           alignment: .leading)
                if isEnabled && !parts.unit.isEmpty {
                    Text(parts.unit).typeStyle(.unit).foregroundStyle(Tokens.Deck.quietInk)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isEnabled ? parameter.readout : "Unavailable")
        } else { Color.clear }
    }

    @ViewBuilder private var track: some View {
        if let parameter {
            switch parameter.control {
            case .dial:
                ParameterDial(parameter: parameter, isEnabled: isEnabled)
                    .padding(.horizontal, -Tokens.Metrics.space16)
            case .shutterDial:
                ShutterDial(parameter: parameter, isEnabled: isEnabled)
                    .padding(.horizontal, -Tokens.Metrics.space16)
            case .contrastFilterDiscs:
                ContrastFilterDiscs(parameter: parameter, filters: model.contrastFilters, isEnabled: isEnabled)
            case .outputStageCards: EmptyView()
            }
        } else { Color.clear }
    }


}

private struct ActiveControlPreview: View {
    @State private var model = EditorModel()
    var body: some View {
        VStack(spacing: Tokens.Metrics.space20) {
            ActiveControl(parameter: model.parameters(for: .light).first, model: model)
            ActiveControl(parameter: model.parameters(for: .light).first { $0.id == .temperature }, model: model)
            ActiveControl(parameter: model.parameters(for: .lab).first { $0.id == .vignette }, model: model)
            ActiveControl(parameter: model.parameters(for: .adjust).first { $0.id == .highlights }, model: model)
            ActiveControl(parameter: model.parameters(for: .light).first, model: model)
        }
        .padding(.horizontal, Tokens.Metrics.space16).background(Tokens.Palette.deck)
    }
}

#Preview("112 pt · bipolar, live caption, empty caption, adjustment, error") {
    ActiveControlPreview().preferredColorScheme(.dark)
}
