import SwiftUI
import FilmEngine

struct ParameterRow: View {
    let model: EditorModel
    let selection: EditorSelection
    var isEnabled = true

    private var parameters: [Parameter] { model.parameters(for: selection.stage) }

    var body: some View {
        HStack(spacing: Tokens.Metrics.space5) {
            if selection.stage == .film { stockSlot }
            if let output = parameters.first(where: { $0.id == .outputStage }) {
                outputSlot(output)
            }
            ViewThatFits(in: .horizontal) {
                chips(compact: false).fixedSize(horizontal: true, vertical: false)
                chips(compact: true).fixedSize(horizontal: true, vertical: false)
                ScrollView(.horizontal) {
                    chips(compact: true).fixedSize(horizontal: true, vertical: false)
                }
                .scrollIndicators(.hidden)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Clip horizontally while preserving the chips' 44 pt hit targets.
            .frame(height: Tokens.Metrics.minimumHitTarget)
            .clipped()
        }
        .frame(height: Tokens.Metrics.chipHeight)
    }

    private func chips(compact: Bool) -> some View {
        HStack(spacing: Tokens.Metrics.space5) {
            ForEach(parameters.filter { $0.id != .outputStage }) { parameter in
                ParameterChip(parameter: parameter,
                              isActive: selection.activeParameter(in: parameters)?.id == parameter.id,
                              isEnabled: isEnabled, compact: compact) {
                    selection.select(parameter.id)
                }
            }
        }
    }

    private var stockSlot: some View {
        Button { selection.isFilmstripOpen = true; Haptics.buttonPress() } label: {
            HStack(spacing: Tokens.Metrics.space5) {
                ZStack {
                    Tokens.Palette.wellTrack
                    if let pixels = model.thumbnails[model.selectedStock] {
                        FilmCanvas(image: pixels)
                    } else {
                        Image(systemName: "photo").foregroundStyle(Tokens.Palette.textQuaternary)
                    }
                }
                .frame(width: Tokens.Deck.thumbnailWidth, height: Tokens.Deck.thumbnailHeight)
                .overlay(alignment: .bottom) {
                    if !model.isIdentity {
                        Tokens.Palette.process(model.profile.metadata.process)
                            .frame(height: Tokens.Deck.processEdge)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Metrics.filmstripCellRadius))
                Text(model.profile.metadata.displayName).typeStyle(.chipName)
                    .lineLimit(1).truncationMode(.tail)
            }
            .padding(.horizontal, Tokens.Deck.chipPadding)
            .frame(width: Tokens.Deck.stockWidth, height: Tokens.Metrics.chipHeight)
            .modifier(DeckFace(selected: isEnabled))
            .frame(height: Tokens.Metrics.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Tokens.Palette.textPrimary)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : Tokens.Deck.unavailableOpacity)
        .accessibilityLabel("Stock")
        .accessibilityValue(model.profile.metadata.displayName)
        .accessibilityHint("Opens the filmstrip")
    }

    private func outputSlot(_ parameter: Parameter) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(model.outputStages.enumerated()), id: \.offset) { index, stage in
                Button {
                    if parameter.value.wrappedValue != Double(index) { Haptics.step() }
                    parameter.value.wrappedValue = Double(index)
                    selection.select(parameter.id)
                } label: {
                    Text(stage.displayName).typeStyle(.chipName)
                        .foregroundStyle(stage == .print && model.outputStage == stage
                                         ? Tokens.Palette.accent : Tokens.Palette.textPrimary)
                        .padding(.horizontal, Tokens.Metrics.segmentRadius)
                        .frame(height: Tokens.Deck.segmentHeight)
                        .modifier(DeckFace(selected: isEnabled && model.outputStage == stage,
                                           restingFill: .clear))
                        .frame(height: Tokens.Metrics.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(parameter.name)
                .accessibilityValue(stage.displayName)
                .accessibilityAddTraits(model.outputStage == stage ? .isSelected : [])
            }
        }
        .frame(height: Tokens.Metrics.chipHeight)
        .recessedSurface(cornerRadius: Tokens.Metrics.chipRadius)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : Tokens.Deck.unavailableOpacity)
    }
}

/// Shared chip face, including the flat empty-photo state.
struct DeckFace: ViewModifier {
    let selected: Bool
    var restingFill: Color = Tokens.Palette.chip

    @ViewBuilder func body(content: Content) -> some View {
        if selected {
            content.raisedSurface(cornerRadius: Tokens.Metrics.chipRadius)
        } else {
            content.background(restingFill, in: RoundedRectangle(cornerRadius: Tokens.Metrics.chipRadius))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Metrics.chipRadius)
                    .strokeBorder(Tokens.Palette.edgeHairline, lineWidth: Tokens.Elevation.hairlineWidth))
        }
    }
}

struct ParameterChip: View {
    let parameter: Parameter
    let isActive: Bool
    var isEnabled = true
    var compact = false
    let select: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Tokens.Metrics.space5) {
            Text(parameter.name).typeStyle(.chipName).lineLimit(1)
                .foregroundStyle(isActive ? Tokens.Palette.accent : Tokens.Palette.textPrimary)
            if parameter.isModified && isEnabled {
                Circle().fill(Tokens.Palette.accent)
                    .frame(width: Tokens.Deck.modifiedDot, height: Tokens.Deck.modifiedDot)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Tokens.Deck.chipPadding)
        .frame(minWidth: compact ? Tokens.Deck.compactChipWidth : nil)
        .frame(height: Tokens.Metrics.chipHeight)
        .modifier(DeckFace(selected: isActive && isEnabled))
        .opacity(isEnabled ? 1 : Tokens.Deck.unavailableOpacity)
        .frame(height: Tokens.Metrics.minimumHitTarget)
        .contentShape(Rectangle())
        .gesture(LongPressGesture().onEnded { _ in reset() }
            .exclusively(before: TapGesture(count: 2).onEnded { reset() }
                .exclusively(before: TapGesture().onEnded { select() })))
        .allowsHitTesting(isEnabled)
        .disabled(!isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(parameter.name)
        .accessibilityInputLabels([parameter.name])
        .accessibilityValue(isEnabled ? parameter.readout : "Unavailable")
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { if isEnabled { select() } }
        .accessibilityAction(named: "Reset to default") { reset() }
    }

    private func reset() {
        guard isEnabled else { return }
        Haptics.reset()
        withAnimation(Tokens.Motion.ease(Tokens.Motion.reset, reduceMotion: reduceMotion)) {
            parameter.value.wrappedValue = parameter.defaultValue
        }
    }
}

#Preview("Chips · default, modified, active, unavailable") {
    VStack(spacing: Tokens.Metrics.space10) {
        ForEach(0..<4) { state in
            ParameterChip(parameter: Parameter(id: .exposure, name: "Exposure", stage: .light,
                value: .constant(state == 1 || state == 2 ? 1 : 0), range: -3...3, step: 1 / 6,
                detent: 0, format: { String(format: "%+.1f EV", $0) }),
                isActive: state == 2, isEnabled: state != 3) {}
        }
    }
    .padding(Tokens.Metrics.space16).background(Tokens.Palette.deck).preferredColorScheme(.dark)
}
