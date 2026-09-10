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
            .background(shape.fill(pressed ? Tokens.Palette.wellSegment : Tokens.Palette.chip))
            .overlay(shape.strokeBorder(Tokens.Palette.edgeHairline,
                                        lineWidth: Tokens.Elevation.hairlineWidth))
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
            .overlay(shape.strokeBorder(Tokens.Palette.wellHairline,
                                        lineWidth: Tokens.Elevation.hairlineWidth))
            .compositingGroup()
    }
}

// MARK: - Indicator

/// The scrubber's indicator. It is neither raised nor recessed: it rides over the
/// track rather than sitting in the deck, so it gets a hairline hard against its
/// own edge to separate it from a light fill, a short cast below, and the accent
/// glow it gains while a finger is on it.
struct Indicator<S: InsettableShape>: ViewModifier {
    let shape: S
    /// `.clear` at rest. Mid-drag, the accent.
    let glow: Color

    func body(content: Content) -> some View {
        content
            .overlay(shape.strokeBorder(Tokens.Palette.shade(Tokens.Elevation.indicatorShade),
                                        lineWidth: Tokens.Elevation.indicatorHairlineWidth))
            .compositingGroup()
            .shadow(color: Tokens.Palette.shade(Tokens.Elevation.indicatorShade),
                    radius: Tokens.Elevation.indicatorCastBlur,
                    y: Tokens.Elevation.indicatorCastOffset)
            .shadow(color: glow, radius: Tokens.Track.indicatorGlowRadius)
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

    /// The scrubber's indicator, riding over the track.
    func indicatorSurface<S: InsettableShape>(_ shape: S, glow: Color = .clear) -> some View {
        modifier(Indicator(shape: shape, glow: glow))
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

// MARK: - Sheet chrome

/// The four weights a full-width action in a sheet can carry.
///
/// `destructive` is red *text* on the standard face rather than a red slab: Cancel
/// is the only destructive control in the Export sheet and a red slab there would
/// read as the primary action. The slab is reserved for swipe-to-delete, which is
/// system-conventional and belongs to the Presets list.
enum SheetActionKind: Sendable {
    case primary, standard, destructive, quiet

    var height: CGFloat {
        self == .quiet ? Tokens.Sheet.quietActionHeight : Tokens.Sheet.actionHeight
    }

    var typeStyle: Tokens.TypeStyle {
        self == .quiet ? .quietAction : .primaryAction
    }

    func ink(enabled: Bool) -> Color {
        guard enabled else { return Tokens.Palette.textDisabled }
        switch self {
        case .primary: return Tokens.Sheet.primaryInk
        case .standard: return Tokens.Palette.textPrimary
        case .destructive: return Tokens.Palette.destructive
        case .quiet: return Tokens.Palette.textSecondary
        }
    }
}

/// A full-width sheet action. Pressing it travels the same millimetre every other
/// pressable in the app does.
struct SheetActionStyle: ButtonStyle {
    var kind: SheetActionKind = .standard

    func makeBody(configuration: Configuration) -> some View {
        SheetActionFace(kind: kind, pressed: configuration.isPressed, label: configuration.label)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.buttonPress() }
            }
    }
}

private struct SheetActionFace<Label: View>: View {
    let kind: SheetActionKind
    let pressed: Bool
    let label: Label
    @Environment(\.isEnabled) private var isEnabled

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Tokens.Metrics.buttonRadius, style: .continuous)
    }

    var body: some View {
        label
            .typeStyle(kind.typeStyle)
            .foregroundStyle(kind.ink(enabled: isEnabled))
            .frame(maxWidth: .infinity)
            .frame(height: kind.height)
            .modifier(SheetActionBackground(kind: kind, pressed: pressed, isEnabled: isEnabled, shape: shape))
            .contentShape(Rectangle())
    }
}

private struct SheetActionBackground: ViewModifier {
    let kind: SheetActionKind
    let pressed: Bool
    let isEnabled: Bool
    let shape: RoundedRectangle

    @ViewBuilder func body(content: Content) -> some View {
        switch kind {
        case .quiet:
            content
        case .primary where isEnabled:
            content
                .background(shape.fill(pressed ? Tokens.Sheet.primaryFacePressed : Tokens.Sheet.primaryFace))
                .overlay(shape.strokeBorder(LinearGradient(colors: [Tokens.Sheet.primaryHighlight, .clear],
                                                           startPoint: .top, endPoint: .bottom),
                                            lineWidth: Tokens.Elevation.highlightWidth))
                .compositingGroup()
                .shadow(color: Tokens.Palette.shade(Tokens.Elevation.castShade),
                        radius: Tokens.Elevation.castBlur, y: Tokens.Elevation.castOffset)
                .offset(y: pressed ? Tokens.Motion.pressDepth : 0)
        case .primary:
            content.background(shape.fill(Tokens.Palette.chip))
        case .standard, .destructive:
            if isEnabled {
                content.raisedSurface(shape, pressed: pressed)
            } else {
                content.background(shape.fill(Tokens.Palette.chip))
            }
        }
    }
}

/// The mono label over a group in a sheet: `FORMAT`, `COLOUR`, `STATE`.
struct SheetSectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .typeStyle(.sectionLabel)
            .foregroundStyle(Tokens.Palette.textQuaternary)
            .accessibilityHidden(true)
    }
}

/// One choice in a sheet's segmented control.
struct SheetSegment<Value: Hashable>: Identifiable {
    let value: Value
    let name: String
    var id: Value { value }

    init(_ value: Value, _ name: String) {
        self.value = value
        self.name = name
    }
}

/// A segmented control in the deck's milled style: a trough with the chosen
/// segment raised out of it.
struct SheetSegmented<Value: Hashable>: View {
    let label: String
    let segments: [SheetSegment<Value>]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(segments) { segment in
                let selected = segment.value == selection
                Button {
                    guard !selected else { return }
                    Haptics.stageSwitch()
                    selection = segment.value
                } label: {
                    Text(segment.name)
                        .typeStyle(selected ? .stageName : .controlName)
                        .foregroundStyle(selected ? Tokens.Palette.textPrimary : Tokens.Palette.textTertiary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: Tokens.Sheet.segmentHeight)
                        .background {
                            if selected {
                                Color.clear.raisedSurface(cornerRadius: Tokens.Metrics.trackRadius)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(Tokens.Sheet.segmentedPadding)
        .frame(height: Tokens.Sheet.segmentedHeight)
        .recessedSurface(cornerRadius: Tokens.Sheet.segmentedRadius)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// The chrome every detented sheet wears: the grabber, the title and its `Done`,
/// and the 20 pt gutter everything inside sits in.
struct SheetSurface<Content: View>: View {
    let title: String
    var isDoneEnabled = true
    let done: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Sheet.rowGap) {
            RoundedRectangle(cornerRadius: Tokens.Sheet.grabberRadius, style: .continuous)
                .fill(Tokens.Sheet.grabber)
                .frame(width: Tokens.Sheet.grabberWidth, height: Tokens.Sheet.grabberHeight)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            HStack {
                Text(title).typeStyle(.sheetTitle).foregroundStyle(Tokens.Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Tokens.Metrics.space16)
                Button("Done") { Haptics.buttonPress(); done() }
                    .typeStyle(.sheetAction)
                    .foregroundStyle(isDoneEnabled ? Tokens.Palette.accent : Tokens.Palette.textDisabled)
                    .disabled(!isDoneEnabled)
            }
            content
        }
        .padding(.top, Tokens.Sheet.topPadding)
        .padding(.horizontal, Tokens.Metrics.space20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Tokens.Palette.sheet)
    }
}

extension View {
    /// A recessed card: the tile grid, the finished record, the Preset list.
    func sheetCard(padding: CGFloat = Tokens.Sheet.cardPadding) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .recessedSurface(cornerRadius: Tokens.Sheet.cardRadius)
    }

    /// The detent, the surface and the corner radius §9 gives every sheet. The
    /// system's own drag indicator is hidden because the sheet draws its own.
    func filmSheet() -> some View {
        presentationDetents([.height(Tokens.Sheet.detentHeight), .large])
            .presentationDragIndicator(.hidden)
            .presentationBackground(Tokens.Palette.sheet)
            .presentationCornerRadius(Tokens.Metrics.sheetRadius)
            .preferredColorScheme(.dark)
    }
}

private struct SheetCatalogue: View {
    @State private var format = "HEIF"

    var body: some View {
        SheetSurface(title: "Export", done: {}) {
            VStack(alignment: .leading, spacing: Tokens.Sheet.sectionGap) {
                VStack(alignment: .leading, spacing: Tokens.Sheet.labelGap) {
                    SheetSectionLabel("Format")
                    SheetSegmented(label: "Format",
                                   segments: [SheetSegment("HEIF", "HEIF"), SheetSegment("JPEG", "JPEG"),
                                              SheetSegment("TIFF", "16-bit TIFF")],
                                   selection: $format)
                }
                Button("Export photo") {}.buttonStyle(SheetActionStyle(kind: .primary))
                Button("Export LUT (.cube)") {}.buttonStyle(SheetActionStyle(kind: .standard))
                Button("Cancel") {}.buttonStyle(SheetActionStyle(kind: .destructive))
                Button("Export another") {}.buttonStyle(SheetActionStyle(kind: .quiet))
                Button("Export photo") {}.buttonStyle(SheetActionStyle(kind: .primary)).disabled(true)
                Text("A card the sheets share.").typeStyle(.caption)
                    .foregroundStyle(Tokens.Palette.textTertiary).sheetCard()
                HStack(spacing: Tokens.Metrics.space10) {
                    DevelopingFrame().frame(width: Tokens.Filmstrip.cellWidth,
                                            height: Tokens.Filmstrip.cellHeight)
                    DevelopingFrame(showsCaption: false)
                        .frame(width: Tokens.Presets.thumbnailWidth, height: Tokens.Presets.thumbnailHeight)
                }
            }
        }
    }
}

#Preview("Sheet chrome · actions and segments") {
    SheetCatalogue().preferredColorScheme(.dark)
}

// MARK: - Developing

/// A frame whose render has not arrived yet, hatched rather than spun. Every
/// surface that renders film into a cell — the filmstrip, the Preset rows, the
/// contact sheet — waits the same way, and never with a spinner: these are sheets
/// about looking at film.
struct DevelopingFrame: View {
    /// Off for a cell too small to set the word in.
    var showsCaption = true

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Tokens.Filmstrip.hatchBase))
            for x in stride(from: -size.height, to: size.width, by: Tokens.Filmstrip.hatchWidth * 2) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                path.addLine(to: CGPoint(x: x + size.height + Tokens.Filmstrip.hatchWidth, y: 0))
                path.addLine(to: CGPoint(x: x + Tokens.Filmstrip.hatchWidth, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(Tokens.Filmstrip.hatchStripe))
            }
        }
        .overlay(alignment: .bottom) {
            if showsCaption {
                Text("developing…").typeStyle(.filmIndex).foregroundStyle(Tokens.Deck.captionInk)
                    .padding(.bottom, Tokens.Filmstrip.developingInset)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Real Liquid Glass on iOS 26; the supported iOS 17–18 releases retain a
/// material fallback. Accessibility substitutes an opaque surface at any OS.
struct EditorGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(red: 0.11, green: 0.11, blue: 0.125), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: contrast == .increased ? 1 : 0.5))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
                .overlay(Capsule().strokeBorder(.white.opacity(contrast == .increased ? 0.5 : 0), lineWidth: 1))
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: contrast == .increased ? 1 : 0.5))
        }
    }
}
