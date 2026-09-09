import SwiftUI

/// The three surfaces every pressable and every trough in the editor is made of.
/// They live here so no component file inlines a shadow.
///
/// The target is one or two millimetres of implied depth: a face that catches
/// light along its top edge and casts a short shadow, a well that swallows it.
/// No bevels for their own sake, no gloss.
///
/// SwiftUI has no inset shadow, so both inset forms are drawn the same way — a
/// stroke wider than the shadow, offset, blurred, then clipped back to the shape
/// so only the inner half survives.
enum Surfaces {
    /// Which gradient a raised face uses. Small icon buttons sit one step lower
    /// than a full-width face.
    enum Face: Sendable {
        case standard, icon

        func gradient(pressed: Bool) -> LinearGradient {
            switch (self, pressed) {
            case (.standard, false): Tokens.Palette.raisedFace
            case (.standard, true): Tokens.Palette.raisedFacePressed
            case (.icon, false): Tokens.Palette.raisedIcon
            case (.icon, true): Tokens.Palette.raisedIconPressed
            }
        }
    }

    /// How deep a well reads. A scrubber track is deeper than a segmented trough.
    enum Depth: Sendable {
        case trough, track

        var blur: CGFloat { self == .trough ? Tokens.Elevation.troughBlur : Tokens.Elevation.trackBlur }
        var shade: Double { self == .trough ? Tokens.Elevation.troughShade : Tokens.Elevation.trackShade }
    }
}

// MARK: - Inset shadow

/// A shadow cast inward from a shape's edge. `blur` of zero gives a crisp line.
struct InsetShadow<S: InsettableShape>: View {
    let shape: S
    let colour: Color
    let blur: CGFloat
    let offsetY: CGFloat

    var body: some View {
        shape
            .stroke(colour, lineWidth: (blur + abs(offsetY)) * 2)
            .offset(y: offsetY)
            .blur(radius: blur)
            .clipShape(shape)
            .allowsHitTesting(false)
    }
}

// MARK: - Raised

struct Raised<S: InsettableShape>: ViewModifier {
    let shape: S
    let pressed: Bool
    let face: Surfaces.Face

    func body(content: Content) -> some View {
        content
            .background(shape.fill(face.gradient(pressed: pressed)))
            .overlay(topEdge)
            .overlay(shape.strokeBorder(Tokens.Palette.edgeHairline,
                                        lineWidth: Tokens.Elevation.hairlineWidth))
            .compositingGroup()
            // A pressed face has already travelled its millimetre, so it casts a
            // shorter shadow than one at rest.
            .shadow(color: Tokens.Palette.shade(Tokens.Elevation.castShade),
                    radius: pressed ? Tokens.Elevation.castBlurPressed : Tokens.Elevation.castBlur,
                    y: pressed ? Tokens.Elevation.castOffsetPressed : Tokens.Elevation.castOffset)
            .offset(y: pressed ? Tokens.Motion.pressDepth : 0)
    }

    /// At rest, a 1 pt highlight along the top edge, fading out down the sides.
    /// Pressed, that highlight flips to a shadow falling in from above.
    @ViewBuilder private var topEdge: some View {
        if pressed {
            InsetShadow(shape: shape,
                        colour: Tokens.Palette.shade(Tokens.Elevation.pressedInsetShade),
                        blur: Tokens.Elevation.pressedInsetBlur,
                        offsetY: Tokens.Elevation.pressedInsetOffset)
        } else {
            shape.strokeBorder(
                LinearGradient(colors: [Tokens.Palette.edgeHighlight, .clear],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: Tokens.Elevation.highlightWidth)
        }
    }
}

// MARK: - Recessed

struct Recessed<S: InsettableShape>: ViewModifier {
    let shape: S
    let fill: Color
    let depth: Surfaces.Depth

    func body(content: Content) -> some View {
        content
            .background(shape.fill(fill))
            .overlay(InsetShadow(shape: shape,
                                 colour: Tokens.Palette.shade(depth.shade),
                                 blur: depth.blur,
                                 offsetY: Tokens.Elevation.wellInsetOffset))
            .overlay(shape.strokeBorder(Tokens.Palette.wellHairline,
                                        lineWidth: Tokens.Elevation.hairlineWidth))
            .compositingGroup()
    }
}

// MARK: - Use

extension View {
    /// A pressable face. Pressing darkens it and translates the whole button
    /// down a point.
    func raisedSurface<S: InsettableShape>(_ shape: S, pressed: Bool = false, face: Surfaces.Face = .standard) -> some View {
        modifier(Raised(shape: shape, pressed: pressed, face: face))
    }

    func raisedSurface(cornerRadius: CGFloat = Tokens.Metrics.buttonRadius,
                       pressed: Bool = false,
                       face: Surfaces.Face = .standard) -> some View {
        raisedSurface(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                      pressed: pressed, face: face)
    }

    /// A trough or a track: light falls in and does not come back out.
    func recessedSurface<S: InsettableShape>(_ shape: S,
                                             fill: Color = Tokens.Palette.wellSegment,
                                             depth: Surfaces.Depth = .trough) -> some View {
        modifier(Recessed(shape: shape, fill: fill, depth: depth))
    }

    func recessedSurface(cornerRadius: CGFloat = Tokens.Metrics.troughRadius,
                         fill: Color = Tokens.Palette.wellSegment,
                         depth: Surfaces.Depth = .trough) -> some View {
        recessedSurface(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                        fill: fill, depth: depth)
    }
}

// MARK: - Preview

/// Every surface side by side, at rest and pressed, over the deck they sit on.
private struct SelectedSegment: ViewModifier {
    let selected: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if selected {
            content.raisedSurface(cornerRadius: Tokens.Metrics.segmentRadius)
        } else {
            content
        }
    }
}

private struct SurfaceCatalogue: View {
    @State private var pressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Metrics.space20) {
            row("Raised · rest") {
                label("Export").raisedSurface()
            }
            row("Raised · pressed") {
                label("Export").raisedSurface(pressed: true)
            }
            row("Raised · icon") {
                icon("photo").raisedSurface(cornerRadius: Tokens.Metrics.chipRadius, face: .icon)
                icon("square.and.arrow.up").raisedSurface(cornerRadius: Tokens.Metrics.chipRadius,
                                                          pressed: true, face: .icon)
            }
            row("Recessed · trough") {
                HStack(spacing: 0) {
                    ForEach(["Light", "Film", "Lab"], id: \.self) { stage in
                        let selected = stage == "Film"
                        Text(stage)
                            .typeStyle(.stageName)
                            .foregroundStyle(selected ? Tokens.Palette.textPrimary
                                                      : Tokens.Palette.textTertiary)
                            .frame(maxWidth: .infinity)
                            .frame(height: Tokens.Metrics.chipHeight)
                            .modifier(SelectedSegment(selected: selected))
                    }
                }
                .padding(3)
                .recessedSurface(cornerRadius: Tokens.Metrics.troughRadius)
            }
            row("Recessed · track") {
                Capsule().fill(Tokens.Palette.accent)
                    .frame(width: 3, height: 18)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 28)
                    .recessedSurface(cornerRadius: Tokens.Metrics.trackRadius,
                                     fill: Tokens.Palette.wellTrack, depth: .track)
            }
            Button("Toggle pressed state") { pressed.toggle() }
                .typeStyle(.chipName)
                .foregroundStyle(Tokens.Palette.accent)
            row("Live") {
                label("Presets").raisedSurface(pressed: pressed)
            }
        }
        .padding(Tokens.Metrics.space20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tokens.Palette.deck)
    }

    private func row(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Metrics.space6) {
            Text(title).typeStyle(.actionLabel).foregroundStyle(Tokens.Palette.textTertiary)
            HStack(spacing: Tokens.Metrics.space10) { content() }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .typeStyle(.controlName)
            .foregroundStyle(Tokens.Palette.textPrimary)
            .padding(.horizontal, Tokens.Metrics.space16)
            .frame(height: Tokens.Metrics.chipHeight)
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .foregroundStyle(Tokens.Palette.textSecondary)
            .frame(width: Tokens.Metrics.chipHeight, height: Tokens.Metrics.chipHeight)
    }
}

#Preview("Surfaces · dark") {
    SurfaceCatalogue().preferredColorScheme(.dark)
}

#Preview("Surfaces · light") {
    SurfaceCatalogue().preferredColorScheme(.light)
}
