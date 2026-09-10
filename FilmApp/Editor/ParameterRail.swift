import SwiftUI

/// A snapping, centre-selected rail. Group separators occupy their own slots,
/// but only parameters are scroll targets, so it never rests on a boundary.
struct ParameterRail: View {
    let model: EditorModel
    let selection: EditorSelection
    let parameters: [Parameter]
    @State private var centered: Parameter.Identity?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(parameters) { parameter in
                        puck(parameter)
                            .frame(width: Tokens.Rail.pitch, height: Tokens.Rail.band)
                            .id(parameter.id)
                            .overlay(alignment: .leading) {
                                if let index = parameters.firstIndex(where: { $0.id == parameter.id }),
                                   index > 0, parameters[index - 1].stage != parameter.stage {
                                    separator(parameter.stage).offset(x: -13)
                                }
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, max(0, (geometry.size.width - Tokens.Rail.pitch) / 2), for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centered, anchor: .center)
            .onChange(of: centered) { _, id in
                if let id { selection.select(id) }
            }
            .onChange(of: selection.activeParameter, initial: true) {
                withAnimation(reduceMotion ? nil : .timingCurve(0.22, 0.8, 0.28, 1, duration: 0.22)) {
                    centered = selection.activeParameter
                }
            }
        }
        .frame(height: Tokens.Rail.band)
        .accessibilityRepresentation {
            VStack {
                Text("Parameter rail")
                    .accessibilityValue("\(selection.stage.displayName), \(selection.activeParameter(in: parameters)?.name ?? "")")
                    .accessibilityAdjustableAction { selection.move($0 == .increment ? 1 : -1) }
                ForEach(parameters) { parameter in
                    Button { selection.select(parameter.id) } label: { Text(parameter.name) }
                        .accessibilityLabel("\(parameter.stage.displayName), \(parameter.name)")
                        .accessibilityValue(parameter.readout)
                        .accessibilityAddTraits(selection.activeParameter == parameter.id ? .isSelected : [])
                }
            }
        }
    }

    private func separator(_ stage: EditorStage) -> some View {
        VStack(spacing: 3) {
            Rectangle().fill(.white.opacity(0.16)).frame(width: 0.5, height: 30)
            Text(stage.displayName.uppercased()).font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(width: 26).offset(y: 8).accessibilityHidden(true)
    }

    private func puck(_ parameter: Parameter) -> some View {
        let selected = selection.activeParameter == parameter.id
        return Button { selection.select(parameter.id) } label: {
            ZStack {
                Circle().fill(RadialGradient(colors: selected ? [Tokens.Rail.selectedCenter, Tokens.Rail.selectedEdge]
                                              : [Tokens.Rail.restCenter, Tokens.Rail.restEdge],
                                            center: .top, startRadius: 0, endRadius: 64))
                ParameterMark(parameter: parameter, model: model)
                    .frame(width: parameter.id == .stock ? 44 : 24, height: parameter.id == .stock ? 44 : 24)
                if parameter.isModified {
                    Circle().fill(Tokens.Palette.accent).frame(width: 5, height: 5).offset(x: 17, y: -17)
                }
            }
            .frame(width: 56, height: 56)
            .overlay(Circle().strokeBorder(.white.opacity(selected ? 0.16 : 0.1), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.7), radius: 3, y: 2)
            .overlay(Circle().stroke(selected ? Tokens.Palette.deck : .clear, lineWidth: 8))
            .overlay(Circle().stroke(selected ? Tokens.Palette.accent : .clear, lineWidth: 2))
            .scaleEffect(selected ? 64 / 56 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.09), value: selected)
        }
        .buttonStyle(PuckPress())
        .accessibilityLabel("\(parameter.stage.displayName), \(parameter.name)")
        .accessibilityValue(parameter.readout)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct PuckPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

private struct ParameterMark: View {
    let parameter: Parameter
    let model: EditorModel
    @ViewBuilder var body: some View {
        switch parameter.id {
        case .stock:
            ZStack(alignment: .bottom) {
                if let pixels = model.thumbnails[model.selectedStock] {
                    FilmCanvas(image: pixels).aspectRatio(CGFloat(pixels.width) / CGFloat(pixels.height), contentMode: .fill)
                } else { DevelopingFrame(showsCaption: false) }
                if model.selectedStock != "identity" {
                    Tokens.Palette.process(model.profile.metadata.process).frame(height: 3)
                }
            }.clipShape(Circle())
        case .exposure, .outputStage:
            Circle().fill(Tokens.Palette.textPrimary)
                .overlay(alignment: .leading) { Rectangle().fill(.black).frame(width: 12) }
                .clipShape(Circle()).overlay(Circle().strokeBorder(Tokens.Palette.textPrimary, lineWidth: 1.5))
                .rotationEffect(.degrees(parameter.id == .outputStage ? 45 : 0))
        case .temperature: sweep([Color(red: 0.31, green: 0.5, blue: 0.78), Color(red: 0.85, green: 0.64, blue: 0.35)])
        case .tint: sweep([Color(red: 0.31, green: 0.6, blue: 0.29), Color(red: 0.71, green: 0.35, blue: 0.66)])
        case .development:
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(1...3, id: \.self) { i in Rectangle().fill(Tokens.Palette.textPrimary).frame(width: 5, height: CGFloat(i * 7)) }
            }
        case .bloom, .halation, .vignette:
            Circle().fill(RadialGradient(colors: [parameter.id == .halation ? Color(red: 1, green: 0.75, blue: 0.55) : Tokens.Palette.textPrimary, .clear], center: .center, startRadius: 0, endRadius: 12))
        case .grain:
            Canvas { context, _ in
                for x in stride(from: 3, to: 24, by: 6) {
                    for y in stride(from: 3, to: 24, by: 6) {
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(Tokens.Palette.textPrimary))
                    }
                }
            }.clipShape(Circle())
        case .frameBorder: Rectangle().strokeBorder(Tokens.Palette.textPrimary, lineWidth: 2.5)
        default: Image(systemName: symbol).font(.system(size: 23, weight: .regular)).foregroundStyle(Tokens.Palette.textPrimary)
        }
    }
    private func sweep(_ colors: [Color]) -> some View {
        Circle().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
    }
    private var symbol: String {
        switch parameter.id {
        case .exposureTime: "timer"
        case .contrastFilter: "camera.filters"
        case .gateWeave: "rectangle.split.3x1"
        case .brilliance: "sun.max"
        case .highlights: "sun.max.fill"
        case .shadows: "moon.fill"
        case .contrast: "circle.lefthalf.filled"
        case .brightness: "sun.min"
        case .blackPoint: "circle.bottomhalf.filled"
        case .saturation: "drop.fill"
        case .vibrance: "drop.halffull"
        default: "circle"
        }
    }
}

extension Tokens {
    enum Rail {
        static let restCenter = Color(red: 35 / 255, green: 35 / 255, blue: 39 / 255)
        static let restEdge = Color(red: 23 / 255, green: 23 / 255, blue: 25 / 255)
        static let selectedCenter = Color(red: 42 / 255, green: 42 / 255, blue: 47 / 255)
        static let selectedEdge = Color(red: 27 / 255, green: 27 / 255, blue: 31 / 255)
        static let pitch: CGFloat = 76
        static let band: CGFloat = 72
    }
}
