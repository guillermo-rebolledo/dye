import SwiftUI
import FilmEngine

struct ContrastFilterDiscs: View {
    let parameter: Parameter
    let filters: [ContrastFilter]
    var isEnabled = true

    var body: some View {
        HStack(spacing: Tokens.Metrics.space10) {
            ForEach(Array(filters.enumerated()), id: \.offset) { index, filter in
                Button {
                    guard parameter.value.wrappedValue != Double(index) else { return }
                    parameter.value.wrappedValue = Double(index)
                    Haptics.step()
                } label: {
                    glass(filter)
                        .frame(width: Tokens.Discrete.discDiameter, height: Tokens.Discrete.discDiameter)
                        .overlay {
                            if Int(parameter.value.wrappedValue.rounded()) == index {
                                Circle().stroke(Tokens.Palette.deck, lineWidth: Tokens.Discrete.selectionHalo)
                                    .padding(-Tokens.Discrete.selectionHalo)
                                Circle().stroke(Tokens.Palette.accent, lineWidth: Tokens.Discrete.selectionRing)
                            }
                        }
                        .frame(width: Tokens.Metrics.minimumHitTarget, height: Tokens.Metrics.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(filter.displayName)
                .accessibilityValue(parameter.format(Double(index)))
                .accessibilityAddTraits(Int(parameter.value.wrappedValue.rounded()) == index ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Tokens.Track.height)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : Tokens.Deck.unavailableOpacity)
    }

    @ViewBuilder private func glass(_ filter: ContrastFilter) -> some View {
        if filter == .none {
            Circle().strokeBorder(Tokens.Palette.textQuaternary, lineWidth: Tokens.Discrete.selectionRing)
        } else {
            Circle().fill(Tokens.Discrete.glass(filter))
                .overlay(Circle().fill(RadialGradient(colors: [Tokens.Discrete.glassHighlight, .clear],
                    center: UnitPoint(x: 0.35, y: 0.30), startRadius: 0,
                    endRadius: Tokens.Discrete.discDiameter)))
                .overlay(InsetShadow(shape: Circle(), colour: Tokens.Discrete.glassRim,
                                     blur: Tokens.Discrete.glassBlur, offsetY: Tokens.Discrete.glassOffset))
                .indicatorSurface(Circle())
        }
    }
}

private struct ContrastFilterPreview: View {
    @State private var model = EditorModel()
    var body: some View {
        VStack {
            if let parameter = model.parameters(for: .film).first(where: { $0.id == .contrastFilter }) {
                Text(parameter.readout).typeStyle(.unit)
                ContrastFilterDiscs(parameter: parameter, filters: model.contrastFilters)
            }
        }
        .padding(Tokens.Metrics.space16).background(Tokens.Palette.deck)
        .task { await model.loadCatalogue(); model.selectedStock = "tri-x-400"; model.settings.contrastFilter = .yellow }
    }
}

#Preview("Glass · Yellow selected") { ContrastFilterPreview().preferredColorScheme(.dark) }
