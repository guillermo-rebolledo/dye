import SwiftUI
import FilmEngine

/// The control every continuous parameter is edited with: a recessed 28 pt track
/// carrying ticks, a fill, an anchor and an indicator, dragged from anywhere in
/// the deck's width.
///
/// **The drag is relative.** Touching the row at x does not move the value to x;
/// the value moves by as much as the finger does. This is the single behaviour
/// the control exists for, because it is used with a thumb resting over the photo
/// being judged, and an absolute track would throw the value away on first touch
/// just to reach it.
///
/// The hit area is the full row and `minimumHitTarget` tall, taller than the
/// track it draws, so the finger does not have to find the 28 pt band.
///
/// **No throttle.** Every step writes straight to the binding. `EditorModel`'s
/// render loop already coalesces, so a drag renders the latest values rather than
/// every intermediate one; a second throttle here would only put the preview
/// behind the thumb.
struct Scrubber: View {
    let parameter: Parameter
    var isEnabled: Bool = true

    @State private var drag: Drag?

    var body: some View {
        GeometryReader { proxy in
            let track = TrackMap(parameter: parameter, width: proxy.size.width)
            ScrubberTrack(parameter: parameter,
                          value: parameter.value.wrappedValue,
                          isDragging: drag != nil,
                          isAtLimit: drag?.wasAtLimit ?? false,
                          isEnabled: isEnabled)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(gesture(track), including: isEnabled ? .all : .none)
        }
        .frame(height: Tokens.Metrics.minimumHitTarget)
        .accessibilityElement()
        .accessibilityLabel(parameter.name)
        .accessibilityValue(parameter.readout)
        .accessibilityAdjustableAction(adjust)
    }

    // MARK: Dragging

    /// What one drag is carrying: where the finger started in the track's own
    /// coordinates, and enough of the last step to know when a haptic is new.
    private struct Drag {
        var origin: CGFloat
        var value: Double
        var wasAtDetent: Bool
        var wasAtLimit: Bool
    }

    private func gesture(_ track: TrackMap) -> some Gesture {
        // Zero minimum distance, so the first movement of a finger already
        // resting on the deck counts rather than being spent reaching a threshold.
        DragGesture(minimumDistance: 0)
            .onChanged { change in
                var state = drag ?? begin(track)
                let outcome = track.resolve(state.origin + change.translation.width)
                commit(outcome, from: &state)
                drag = state
            }
            .onEnded { _ in drag = nil }
    }

    private func begin(_ track: TrackMap) -> Drag {
        Haptics.prepare()
        let value = parameter.value.wrappedValue
        return Drag(origin: track.origin(of: value),
                    value: value,
                    wasAtDetent: parameter.isAtDetent(value),
                    wasAtLimit: track.isAtLimit(value))
    }

    private func commit(_ outcome: TrackMap.Outcome, from state: inout Drag) {
        let moved = outcome.value != state.value
        if moved { parameter.value.wrappedValue = outcome.value }
        // A fast flick can carry the finger across the whole sticky band between
        // two gesture events, landing on the far side without ever sitting on the
        // detent. It was still crossed, so it is still felt.
        let crossedDetent = parameter.detent.map {
            (state.value - $0) * (outcome.value - $0) < 0
        } ?? false

        // The three speak in order of how much they mean, and only one of them
        // speaks: arriving at the wall is a step too, and arriving at the detent
        // is a step too, and firing both would say each thing twice.
        if outcome.isAtLimit, !state.wasAtLimit {
            Haptics.rangeLimit()
        } else if (outcome.isAtDetent && !state.wasAtDetent) || crossedDetent {
            Haptics.detent()
        } else if moved {
            Haptics.step()
        }
        state.value = outcome.value
        state.wasAtDetent = outcome.isAtDetent
        state.wasAtLimit = outcome.isAtLimit
    }

    /// VoiceOver moves by one step, which is a sixth of a stop on Exposure. The
    /// haptics are the drag's, because arriving at a detent means the same thing
    /// however the value got there — including the wall, which fires on arrival
    /// and then stays quiet however many more times the increment is refused.
    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        let current = parameter.value.wrappedValue
        let step = direction == .increment ? parameter.step : -parameter.step
        let next = TrackMap.settle(current + step, for: parameter)
        guard next != current else { return }
        parameter.value.wrappedValue = next
        if next <= parameter.range.lowerBound || next >= parameter.range.upperBound {
            Haptics.rangeLimit()
        } else if parameter.isAtDetent(next) {
            Haptics.detent()
        } else {
            Haptics.step()
        }
    }

}

// MARK: - The track map

extension Scrubber {
    /// The map between a value and a position on the track, and the only place
    /// that knows about the detent's stickiness. It is `TrackMap` rather than
    /// `Geometry` because `CONTEXT.md` gives Geometry to the Pass that draws the
    /// Vignette, the Gate Weave and the Frame Border.
    ///
    /// Two spaces meet here. A **point** is where something is drawn. A **raw**
    /// position is where the finger is, and the two differ by the 6 pt the
    /// indicator spends held at a detent: `resolve` collapses that band to the
    /// detent and `origin` reverses it, so a drag that starts beside a detent
    /// does not jump on first touch.
    struct TrackMap {
        let parameter: Parameter
        let width: CGFloat

        /// The indicator parks 2 pt inside the end, so half of it plus that inset
        /// is what the track gives up at each end. Every mark on the track uses
        /// this same mapping, which is what keeps the detent tick under the
        /// indicator that is sitting on it.
        var lead: CGFloat { Tokens.Track.indicatorEndInset + Tokens.Track.indicatorWidth / 2 }
        var travel: CGFloat { max(width - 2 * lead, 1) }
        var span: Double { parameter.range.upperBound - parameter.range.lowerBound }

        /// How far past the detent the finger goes before the indicator lets go,
        /// which is the reading `Tokens.Motion.detentStick` documents: 6 pt from
        /// the detent, in either direction. Approached from one side and carried
        /// through, that is 12 pt of finger travel spent held — the release
        /// threshold is the 6 pt, not the width of the band.
        private var stick: CGFloat { Tokens.Motion.detentStick }

        func x(fraction: Double) -> CGFloat { lead + travel * CGFloat(fraction) }
        func x(of value: Double) -> CGFloat { x(fraction: parameter.fraction(of: value)) }

        var detentX: CGFloat? { parameter.detentFraction.map(x(fraction:)) }

        /// The fill runs from here: zero on a bipolar parameter, where the value
        /// departs in a direction, and the left end on a unipolar one, where
        /// there is only one direction to depart in.
        ///
        /// This is deliberately not the detent. Grain runs 0…200 % with its
        /// detent at 100 %, and `1q` fills it from the left; only the anchor
        /// *line* marks the detent.
        var fillOrigin: Double {
            isBipolar ? parameter.fraction(of: 0) : 0
        }

        /// A parameter whose range crosses zero. Exposure, Tint and the
        /// Development Offset; nothing else the deck offers.
        var isBipolar: Bool {
            parameter.range.lowerBound < 0 && parameter.range.upperBound > 0
        }

        /// Whether a value has run into an end of the range. A value that arrived
        /// from a Preset outside the editor's clamp reads as at the limit and
        /// parks at the wall; the readout still tells the truth about it.
        func isAtLimit(_ value: Double) -> Bool {
            value <= parameter.range.lowerBound || value >= parameter.range.upperBound
        }

        // MARK: The two spaces

        /// Where the finger must be for the indicator to sit at `value`.
        func origin(of value: Double) -> CGFloat {
            guard let detentX else { return x(of: value) }
            // A value already on the detent starts in the middle of the sticky
            // band, so it takes the full 6 pt to leave in either direction.
            if parameter.isAtDetent(value) { return detentX }
            let offset = x(of: value) - detentX
            return detentX + offset + (offset < 0 ? -stick : stick)
        }

        /// What a finger at `raw` is asking for, quantised to the step.
        func resolve(_ raw: CGFloat) -> Outcome {
            guard let detentX, let detent = parameter.detent else { return stepped(at: raw) }
            let offset = raw - detentX
            guard abs(offset) > stick else {
                // The detent is exact rather than quantised: a Stock Balance in
                // Kelvin need not fall on a step boundary.
                return Outcome(value: detent, isAtDetent: true, isAtLimit: isAtLimit(detent))
            }
            return stepped(at: detentX + offset - (offset < 0 ? -stick : stick))
        }

        private func stepped(at point: CGFloat) -> Outcome {
            let raw = parameter.range.lowerBound + Double((point - lead) / travel) * span
            let value = Self.settle(raw, for: parameter)
            return Outcome(value: value,
                           isAtDetent: parameter.isAtDetent(value),
                           isAtLimit: isAtLimit(value))
        }

        /// A value on the parameter's step grid and inside its range. The one
        /// place that quantises, so the drag and VoiceOver cannot land on
        /// different grids.
        static func settle(_ raw: Double, for parameter: Parameter) -> Double {
            let lower = parameter.range.lowerBound
            let value = parameter.step > 0
                ? lower + ((raw - lower) / parameter.step).rounded() * parameter.step
                : raw
            return min(max(value, lower), parameter.range.upperBound)
        }

        struct Outcome {
            let value: Double
            let isAtDetent: Bool
            let isAtLimit: Bool
        }

        // MARK: Ticks

        /// Minor ticks are one per step, thinned to the densest multiple of the
        /// step that still leaves them `minimumTickSpacing` apart. Temperature
        /// steps every 50 K across 8000 K, which is 160 ticks over 380 pt and
        /// would draw as a solid band rather than as steps.
        var minorInterval: Double {
            guard parameter.step > 0, span > 0 else { return span }
            let perStep = travel * CGFloat(parameter.step / span)
            guard perStep > 0 else { return span }
            let multiple = max(1, (Tokens.Track.minimumTickSpacing / perStep).rounded(.up))
            return parameter.step * Double(multiple)
        }

        /// A major tick per stop or decade, derived rather than named: the 1, 2 or
        /// 5 times a power of ten nearest a track's worth divided by the target
        /// count. That lands on 1 EV for Exposure, 1000 K for Temperature and
        /// 50 % on the three that run to 200 %.
        var majorInterval: Double {
            let target = span / Tokens.Track.majorTickTarget
            guard target > 0 else { return span }
            let decade = pow(10, log10(target).rounded(.down))
            let normalised = target / decade
            // Geometric boundaries, so each interval wins the range it is nearest
            // to in ratio rather than in difference.
            let choice: Double = normalised < 1.4142 ? 1 : normalised < 3.1623 ? 2 : normalised < 7.0711 ? 5 : 10
            return choice * decade
        }

        /// Every mark of `interval`, aligned to `origin`, that falls in the range.
        func marks(every interval: Double, from origin: Double) -> [Double] {
            guard interval > 0, span > 0 else { return [] }
            let lower = parameter.range.lowerBound
            let first = origin + ((lower - origin) / interval).rounded(.up) * interval
            let count = Int(((parameter.range.upperBound - first) / interval).rounded(.down))
            guard count >= 0 else { return [] }
            // The thinning above keeps this well under a few hundred; the cap is
            // only here so a degenerate range cannot ask for a million lines.
            return (0...min(count, 512)).map { first + Double($0) * interval }
        }
    }
}

// MARK: - Drawing

/// The track and everything on it, with no gesture of its own. Splitting the
/// drawing from the drag is what lets the `#Preview` show mid-drag and every
/// other state as a still, without the view carrying a hook it only needs there.
struct ScrubberTrack: View, Animatable {
    let parameter: Parameter
    var value: Double
    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var isDragging: Bool = false
    /// Whether the drag has run into an end. Not derived from the value, because
    /// three of the Lab parameters rest at zero, which *is* their lower bound,
    /// and a wall lit before anyone touched the control says nothing happened.
    var isAtLimit: Bool = false
    var isEnabled: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Tokens.Metrics.trackRadius, style: .continuous)
    }

    var body: some View {
        GeometryReader { proxy in
            let track = Scrubber.TrackMap(parameter: parameter, width: proxy.size.width)
            ZStack(alignment: .topLeading) {
                Canvas(rendersAsynchronously: false) { context, size in
                    draw(in: context, size: size, track: track)
                }
                if isEnabled {
                    anchor(track)
                    wall(track)
                }
            }
            .clipShape(shape)
            .recessedSurface(shape, fill: Tokens.Palette.wellTrack, depth: .track)
            // The indicator stands proud of the track top and bottom, so it sits
            // outside the clip rather than inside it.
            .overlay(alignment: .topLeading) {
                if isEnabled { indicator(track) }
            }
        }
        .frame(height: Tokens.Track.height)
        .opacity(isEnabled ? 1 : Tokens.Track.disabledOpacity)
    }

    // MARK: Ticks and fill

    private func draw(in context: GraphicsContext, size: CGSize, track: Scrubber.TrackMap) {
        ticks(in: context, size: size, track: track,
              interval: track.minorInterval, origin: parameter.range.lowerBound,
              inset: Tokens.Track.tickInsetMinor, colour: Tokens.Palette.tickMinor)
        ticks(in: context, size: size, track: track,
              interval: track.majorInterval, origin: 0,
              inset: Tokens.Track.tickInsetMajor, colour: Tokens.Palette.tickMajor)
        // The fill goes on last, over the ticks, the way `1q` layers them.
        if isEnabled { fill(in: context, size: size, track: track) }
    }

    private func ticks(in context: GraphicsContext, size: CGSize, track: Scrubber.TrackMap,
                       interval: Double, origin: Double, inset: CGFloat, colour: Color) {
        var path = Path()
        for mark in track.marks(every: interval, from: origin) {
            let x = track.x(fraction: parameter.fraction(of: mark)) - Tokens.Track.tickWidth / 2
            path.addRect(CGRect(x: x, y: inset,
                                width: Tokens.Track.tickWidth, height: size.height - inset * 2))
        }
        context.fill(path, with: .color(colour))
    }

    private func fill(in context: GraphicsContext, size: CGSize, track: Scrubber.TrackMap) {
        let origin = track.x(fraction: track.fillOrigin)
        let head = track.x(of: value)
        let rect = CGRect(x: min(origin, head), y: 0, width: abs(head - origin), height: size.height)
        context.fill(Path(rect), with: .color(Tokens.Palette.trackFill))
    }

    // MARK: Anchor, wall, indicator

    /// The line the fill runs from. A unipolar parameter anchors at its own left
    /// wall, where a line would only draw over the end of the track, so it has
    /// none. On the detent the line becomes accent and lights.
    @ViewBuilder private func anchor(_ track: Scrubber.TrackMap) -> some View {
        if let fraction = parameter.detentFraction, fraction > 0 {
            let onDetent = parameter.isAtDetent(value)
            Rectangle()
                .fill(onDetent ? Tokens.Palette.trackAnchorActive : Tokens.Palette.trackAnchor)
                .frame(width: Tokens.Track.anchorWidth, height: Tokens.Track.height)
                .shadow(color: onDetent ? Tokens.Palette.trackAnchorGlow : .clear,
                        radius: Tokens.Track.anchorGlowRadius)
                .position(x: track.x(fraction: fraction), y: Tokens.Track.height / 2)
                .animation(Tokens.Motion.ease(Tokens.Motion.tick, reduceMotion: reduceMotion), value: onDetent)
        }
    }

    /// The end the value has run into. No rubber-band and no bounce: the wall
    /// lights and that is the whole of the feedback.
    @ViewBuilder private func wall(_ track: Scrubber.TrackMap) -> some View {
        if isAtLimit {
            let atUpper = value >= parameter.range.upperBound
            Rectangle()
                .fill(Tokens.Palette.trackWall)
                .frame(width: Tokens.Track.wallWidth, height: Tokens.Track.height)
                .position(x: atUpper ? track.width - Tokens.Track.wallWidth / 2 : Tokens.Track.wallWidth / 2,
                          y: Tokens.Track.height / 2)
        }
    }

    private func indicator(_ track: Scrubber.TrackMap) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Track.indicatorRadius, style: .continuous)
        return shape
            .fill(isDragging ? Tokens.Palette.indicatorFaceDragging : Tokens.Palette.indicatorFace)
            .indicatorSurface(shape, glow: isDragging ? Tokens.Palette.indicatorGlow : .clear)
            .frame(width: Tokens.Track.indicatorWidth,
                   height: Tokens.Track.height + Tokens.Track.indicatorOverhang * 2)
            .position(x: track.x(of: value), y: Tokens.Track.height / 2)
    }
}

// MARK: - Preview

/// Every state the ticket names, as stills, over one live scrubber that actually
/// drags. The stills are `ScrubberTrack` because mid-drag and at-detent are
/// moments rather than settings; the live row underneath is the real control and
/// is what the drag, the detent stick and the range wall are judged on.
private struct ScrubberCatalogue: View {
    @State private var exposure: Double = 0.5
    @State private var grain: Double = 1

    /// Sample values, not the deck: a Stock is not loaded here. The ranges, steps
    /// and detents are the ones `Parameter.swift` gives these same controls.
    private func sample(_ id: Parameter.Identity, _ name: String, _ value: Binding<Double>,
                        _ range: ClosedRange<Double>, step: Double, detent: Double?,
                        format: @escaping (Double) -> String) -> Parameter {
        Parameter(id: id, name: name, stage: .light, value: value,
                  range: range, step: step, detent: detent, format: format)
    }

    private var exposureParameter: Parameter {
        sample(.exposure, "Exposure", $exposure, EditorRange.exposure, step: 1 / 6, detent: 0,
               format: { String(format: "%+.1f EV", $0) })
    }

    private func grainParameter(_ value: Binding<Double>) -> Parameter {
        sample(.grain, "Grain", value, RenderSettings.grainRange, step: 0.05, detent: 1,
               format: { String(format: "%.0f%%", $0 * 100) })
    }

    private func temperature(_ value: Double) -> Parameter {
        sample(.temperature, "Temperature", .constant(value), EditorRange.temperature, step: 50, detent: 5500,
               format: { String(format: "%.0f K", $0) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Metrics.space20) {
                still("rest", grainParameter(.constant(0.76)), value: 0.76)
                still("mid-drag", grainParameter(.constant(1.16)), value: 1.16, isDragging: true)
                still("at detent", grainParameter(.constant(1)), value: 1)
                still("at range limit", grainParameter(.constant(2)), value: 2, isAtLimit: true)
                still("disabled", grainParameter(.constant(0.76)), value: 0.76, isEnabled: false)
                still("bipolar · exposure", exposureParameter, value: -1)
                still("dense steps · temperature", temperature(6200), value: 6200)

                Text("live")
                    .typeStyle(.actionLabel).foregroundStyle(Tokens.Palette.textTertiary)
                live("Exposure", exposureParameter)
                live("Grain", grainParameter($grain))
            }
            .padding(Tokens.Metrics.space16)
        }
        .background(Tokens.Palette.deck)
    }

    private func still(_ title: String, _ parameter: Parameter, value: Double,
                       isDragging: Bool = false, isAtLimit: Bool = false,
                       isEnabled: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Metrics.space6) {
            header(title, parameter, value: value)
            ScrubberTrack(parameter: parameter, value: value, isDragging: isDragging,
                          isAtLimit: isAtLimit, isEnabled: isEnabled)
        }
    }

    private func live(_ title: String, _ parameter: Parameter) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Metrics.space6) {
            header(title, parameter, value: parameter.value.wrappedValue)
            Scrubber(parameter: parameter)
        }
    }

    /// The readout the ticket says must not jitter while a drag runs: fixed-width
    /// SF Mono in a slot that reserves its own height.
    private func header(_ title: String, _ parameter: Parameter, value: Double) -> some View {
        HStack {
            Text(title).typeStyle(.actionLabel).foregroundStyle(Tokens.Palette.textTertiary)
            Spacer()
            Text(parameter.format(value))
                .typeStyle(.unit).foregroundStyle(Tokens.Palette.textPrimary)
            if let tag = parameter.tag(at: value) {
                Text(tag == .off ? "● off" : "● detent")
                    .typeStyle(.tag).foregroundStyle(Tokens.Palette.accent)
            }
        }
        .frame(height: Tokens.TypeStyle.unit.slotHeight)
    }
}

#Preview("Scrubber · dark") {
    ScrubberCatalogue().preferredColorScheme(.dark)
}

#Preview("Scrubber · light") {
    ScrubberCatalogue().preferredColorScheme(.light)
}
