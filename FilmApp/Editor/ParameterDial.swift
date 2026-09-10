import SwiftUI
import FilmEngine

/// A horizontal dial: the graduated tape moves beneath a fixed center hairline.
/// Touch is relative, with stepped values, sticky detents, and a full 44 pt hit area.
/// The renderer already coalesces updates, so every step writes to the binding.
struct ParameterDial: View {
    let parameter: Parameter
    var isEnabled: Bool = true
    var onDragging: (Bool) -> Void = { _ in }

    @State private var drag: Drag?

    var body: some View {
        GeometryReader { _ in
            let track = TrackMap.dial(for: parameter)
            ParameterDialTrack(parameter: parameter,
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
        .accessibilityValue(isEnabled ? parameter.readout : "Unavailable")
        .accessibilityAdjustableAction(adjust)
        .disabled(!isEnabled)
        .onDisappear { onDragging(false) }
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
                if drag == nil { onDragging(true) }
                var state = drag ?? begin(track)
                guard change.translation.width != 0 else { return }
                let outcome = track.resolve(state.origin - change.translation.width)
                commit(outcome, from: &state)
                drag = state
            }
            .onEnded { _ in drag = nil; onDragging(false) }
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
        if (outcome.isAtDetent && !state.wasAtDetent) || crossedDetent {
            Haptics.detent()
        } else if outcome.isAtLimit, !state.wasAtLimit {
            Haptics.rangeLimit()
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
        guard isEnabled else { return }
        let current = parameter.value.wrappedValue
        let step = direction == .increment ? parameter.step : -parameter.step
        var next = TrackMap.settle(current + step, for: parameter)
        if let detent = parameter.detent, (current - detent) * (next - detent) < 0 {
            next = detent
        }
        guard next != current else { return }
        parameter.value.wrappedValue = next
        if parameter.isAtDetent(next) && !parameter.isAtDetent(current) {
            Haptics.detent()
        } else if next <= parameter.range.lowerBound || next >= parameter.range.upperBound {
            Haptics.rangeLimit()
        } else {
            Haptics.step()
        }
    }

}

// MARK: - The track map

extension ParameterDial {
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

        /// Fixed spacing per step lets the tape extend beyond the viewport.
        /// Shutter speeds retain the handoff's 54 pt per stop / 18 pt per third stop.
        static func dial(for parameter: Parameter) -> Self {
            let pointsPerStep = parameter.pointsPerStep
            let span = parameter.range.upperBound - parameter.range.lowerBound
            let travel = CGFloat(span / max(parameter.step, .ulpOfOne)) * pointsPerStep
            return Self(parameter: parameter,
                        width: travel + 2 * (Tokens.Track.indicatorEndInset + Tokens.Track.indicatorWidth / 2))
        }

        /// Logical tape coordinates include an inset at each end. Rendering
        /// translates these coordinates so the current value sits at the center.
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
            let outcome = stepped(at: detentX + offset - (offset < 0 ? -stick : stick))
            // An off-grid detent must not round back across itself on release.
            // Stay at the detent until the next step in the drag direction.
            let value = offset < 0 ? min(outcome.value, detent) : max(outcome.value, detent)
            return Outcome(value: value, isAtDetent: parameter.isAtDetent(value), isAtLimit: isAtLimit(value))
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

        /// What the minor ticks step by. Normally the parameter's own step, which
        /// is what a tick means. A pitch fine enough to make two hundred steps
        /// draggable puts those ticks closer together than the row can resolve,
        /// and a tick row that reads as a solid band has stopped saying anything,
        /// so the ticks thin to a fraction of the major interval instead.
        var minorInterval: Double {
            let pitch = travel / max(span, .ulpOfOne)
            guard parameter.step * pitch < Tokens.Track.minimumTickSpacing else { return parameter.step }
            let major = majorInterval
            let candidates = [major / 10, major / 5, major / 2, major]
            return candidates.first { $0 >= parameter.step && $0 * pitch >= Tokens.Track.minimumTickSpacing }
                ?? major
        }

        /// Every mark of `interval`, aligned to `origin`, that falls in the range.
        func marks(every interval: Double, from origin: Double) -> [Double] {
            guard interval > 0, span > 0 else { return [] }
            let lower = parameter.range.lowerBound
            let first = origin + ((lower - origin) / interval).rounded(.up) * interval
            let count = Int(((parameter.range.upperBound - first) / interval).rounded(.down))
            guard count >= 0 else { return [] }
            // App ranges contain at most a few hundred steps; cap degenerate input.
            return (0...min(count, 512)).map { first + Double($0) * interval }
        }
    }
}

// MARK: - Drawing

/// Drawing is separate so previews can show drag, detent and boundary states.
struct ParameterDialTrack: View, Animatable {
    let parameter: Parameter
    var value: Double
    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var isDragging = false
    var isAtLimit = false
    var isEnabled = true

    var body: some View {
        GeometryReader { proxy in
            let map = ParameterDial.TrackMap.dial(for: parameter)
            Canvas { context, size in
                draw(in: context, size: size, map: map)
            }
            .mask(LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: Tokens.Discrete.tickerFade),
                .init(color: .black, location: 1 - Tokens.Discrete.tickerFade),
                .init(color: .clear, location: 1)
            ], startPoint: .leading, endPoint: .trailing))
            .overlay {
                if isEnabled {
                    Rectangle()
                        .fill(isAtLimit ? Tokens.Palette.trackWall
                              : parameter.isAtDetent(value) ? Tokens.Palette.accent : Tokens.Palette.textPrimary)
                        .frame(width: parameter.isAtDetent(value) ? 3 : 2, height: parameter.isAtDetent(value) ? 24 : 20)
                        .shadow(color: parameter.isAtDetent(value) ? Tokens.Palette.indicatorGlow : .clear,
                                radius: Tokens.Track.indicatorGlowRadius)
                }
            }
            .frame(width: proxy.size.width, height: Tokens.Track.height)
        }
        .frame(height: Tokens.Track.height)
        .opacity(isEnabled ? 1 : Tokens.Track.disabledOpacity)
        .accessibilityHidden(true)
    }

    private func draw(in context: GraphicsContext, size: CGSize, map: ParameterDial.TrackMap) {
        let current = min(max(value, parameter.range.lowerBound), parameter.range.upperBound)
        let pointsPerUnit = map.travel / CGFloat(map.span)
        func x(_ mark: Double) -> CGFloat { size.width / 2 + CGFloat(mark - current) * pointsPerUnit }
        let major = parameter.control == .shutterDial ? 1 : parameter.step * 6
        let labelOrigin = parameter.control == .shutterDial ? parameter.range.lowerBound : 0

        for mark in map.marks(every: map.minorInterval, from: parameter.range.lowerBound) {
            let position = x(mark)
            guard position >= 0, position <= size.width else { continue }
            let tick = CGRect(x: position - Tokens.Track.tickWidth / 2, y: 0,
                              width: Tokens.Track.tickWidth, height: Tokens.Track.tickInsetMinor)
            context.fill(Path(tick), with: .color(.white.opacity(isDragging ? 0.34 : 0.24)))
        }
        for mark in map.marks(every: major, from: labelOrigin) {
            let position = x(mark)
            guard position >= 0, position <= size.width else { continue }
            let tick = CGRect(x: position - Tokens.Track.tickWidth / 2, y: 0,
                              width: Tokens.Track.tickWidth, height: Tokens.Track.dialMajorTickHeight)
            context.fill(Path(tick), with: .color(.white.opacity(isDragging ? 0.60 : 0.45)))

        }
        if isEnabled, let detent = parameter.detent, parameter.range.contains(detent) {
            let tick = CGRect(x: x(detent) - Tokens.Track.anchorWidth / 2, y: 0,
                              width: Tokens.Track.anchorWidth, height: Tokens.Track.dialMajorTickHeight)
            context.fill(Path(tick), with: .color(Tokens.Palette.accent))
        }
        // The finite tape ends at its real bounds. On arrival the end cap lights
        // at the fixed hairline; dragging farther cannot rubber-band the scale.
        for bound in [parameter.range.lowerBound, parameter.range.upperBound] {
            let position = x(bound)
            guard position >= 0, position <= size.width else { continue }
            let cap = CGRect(x: position - Tokens.Track.wallWidth / 2, y: 0,
                             width: Tokens.Track.wallWidth, height: size.height)
            context.fill(Path(cap), with: .color(isAtLimit && current == bound
                                                ? Tokens.Palette.trackWall : Tokens.Palette.tickMajor))
        }
    }
}

// MARK: - Preview

/// Every state the ticket names, as stills, over one live dial that actually
/// drags. The stills are `ParameterDialTrack` because mid-drag and at-detent are
/// moments rather than settings; the live row underneath is the real control and
/// is what the drag, the detent stick and the range wall are judged on.
private struct ParameterDialCatalogue: View {
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
            ParameterDialTrack(parameter: parameter, value: value, isDragging: isDragging,
                               isAtLimit: isAtLimit, isEnabled: isEnabled)
        }
    }

    private func live(_ title: String, _ parameter: Parameter) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Metrics.space6) {
            header(title, parameter, value: parameter.value.wrappedValue)
            ParameterDial(parameter: parameter)
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

#Preview("ParameterDial · dark") {
    ParameterDialCatalogue().preferredColorScheme(.dark)
}

#Preview("ParameterDial · light") {
    ParameterDialCatalogue().preferredColorScheme(.light)
}
