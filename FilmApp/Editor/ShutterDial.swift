import SwiftUI

/// A moving stops-space ruler under a stationary hairline. Its binding and its
/// formatter are the Parameter's; this view never converts settings to seconds.
struct ShutterDial: View, Animatable {
    let parameter: Parameter
    var isEnabled = true
    var displayedValue: Double
    nonisolated var animatableData: Double {
        get { displayedValue }
        set { displayedValue = newValue }
    }
    @State private var origin: CGFloat?

    init(parameter: Parameter, isEnabled: Bool = true) {
        self.parameter = parameter
        self.isEnabled = isEnabled
        displayedValue = parameter.value.wrappedValue
    }

    private var mapping: Scrubber.TrackMap {
        Scrubber.TrackMap(parameter: parameter,
            width: CGFloat(parameter.range.upperBound - parameter.range.lowerBound)
                * Tokens.Discrete.pointsPerStop
                + 2 * (Tokens.Track.indicatorEndInset + Tokens.Track.indicatorWidth / 2))
    }

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let current = displayedValue
                let halfSpan = Double(size.width / Tokens.Discrete.pointsPerStop / 2)
                let lower = max(parameter.range.lowerBound, current - halfSpan)
                let upper = min(parameter.range.upperBound, current + halfSpan)
                if lower <= upper {
                    let first = Int(ceil((lower - parameter.range.lowerBound) / parameter.step))
                    let last = Int(floor((upper - parameter.range.lowerBound) / parameter.step))
                    if first <= last {
                        for index in first...last {
                            let value = parameter.range.lowerBound + Double(index) * parameter.step
                            let x = size.width / 2 + CGFloat(value - current) * Tokens.Discrete.pointsPerStop
                            var tick = Path()
                            tick.move(to: CGPoint(x: x, y: 0))
                            tick.addLine(to: CGPoint(x: x, y: Tokens.Track.tickInsetMinor))
                            context.stroke(tick, with: .color(Tokens.Palette.tickMajor), lineWidth: Tokens.Track.tickWidth)
                            if index.isMultiple(of: 3) {
                                context.draw(Text(parameter.format(value)).font(Tokens.TypeStyle.tag.font)
                                    .foregroundStyle(Tokens.Palette.textSecondary),
                                    at: CGPoint(x: x, y: Tokens.Discrete.tickerLabelY))
                            }
                        }
                    }
                }
                if isEnabled, let detent = parameter.detent {
                    let x = size.width / 2 + CGFloat(detent - current) * Tokens.Discrete.pointsPerStop
                    context.fill(Path(CGRect(x: x - Tokens.Track.anchorWidth / 2, y: 0,
                        width: Tokens.Track.anchorWidth, height: size.height)), with: .color(Tokens.Palette.accent))
                }
            }
            .frame(height: Tokens.Track.height)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                        .init(color: .black, location: Tokens.Discrete.tickerFade),
                                        .init(color: .black, location: 1 - Tokens.Discrete.tickerFade),
                                        .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            .overlay {
                if isEnabled {
                    Rectangle().fill(Tokens.Palette.textPrimary)
                        .frame(width: Tokens.Discrete.hairline, height: Tokens.Track.height)
                }
            }
            .frame(width: proxy.size.width, height: Tokens.Metrics.minimumHitTarget)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { event in
                    guard isEnabled else { return }
                    if origin == nil { origin = mapping.origin(of: parameter.value.wrappedValue); Haptics.prepare() }
                    // Dragging the tape right brings slower positions from its left.
                    commit(mapping.resolve((origin ?? 0) - event.translation.width).value)
                }
                .onEnded { _ in origin = nil })
        }
        .frame(height: Tokens.Metrics.minimumHitTarget)
        .opacity(isEnabled ? 1 : Tokens.Deck.unavailableOpacity)
        .accessibilityElement()
        .accessibilityLabel(parameter.name)
        .accessibilityValue(parameter.readout)
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            let current = parameter.value.wrappedValue
            var next = Scrubber.TrackMap.settle(current + (direction == .increment ? parameter.step : -parameter.step), for: parameter)
            if let detent = parameter.detent, (current - detent) * (next - detent) < 0 { next = detent }
            commit(next)
        }
    }

    private func commit(_ next: Double) {
        let old = parameter.value.wrappedValue
        guard next != old else { return }
        parameter.value.wrappedValue = next
        let crosses = parameter.detent.map { (old - $0) * (next - $0) < 0 } ?? false
        if (parameter.isAtDetent(next) && !parameter.isAtDetent(old)) || crosses {
            Haptics.detent()
        } else if mapping.isAtLimit(next) && !mapping.isAtLimit(old) {
            Haptics.rangeLimit()
        } else { Haptics.step() }
    }
}

private struct ShutterPreview: View {
    @State private var stops = 0.0
    var body: some View {
        ShutterDial(parameter: Parameter(id: .exposureTime, name: "Exposure time", stage: .light,
            value: $stops, range: EditorRange.exposureTimeStops, step: 1 / 3, detent: 0,
            control: .shutterDial, format: { Parameter.shutterSpeed(pow(2, $0)) }))
            .padding(.horizontal, Tokens.Metrics.space16).background(Tokens.Palette.deck)
    }
}

#Preview("Shutter dial · reciprocity threshold at 1 s") { ShutterPreview().preferredColorScheme(.dark) }
