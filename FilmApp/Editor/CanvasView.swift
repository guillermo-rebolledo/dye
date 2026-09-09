import SwiftUI
import FilmEngine
import UIKit.UIGestureRecognizerSubclass

/// Presentation only; FilmCanvas continues to own the Metal and EDR path.
struct CanvasView: View {
    enum Content {
        case empty
        case loading
        case photo(pixels: RenderedPixels, before: RenderedPixels?, milliseconds: Double?)

        var accessibilityLabel: String {
            switch self {
            case .empty: "Open a photo. Choose a photo to begin."
            case .loading: "Decoding…"
            case .photo: "Rendered photo"
            }
        }

        var hasPhoto: Bool {
            if case .photo = self { return true }
            return false
        }
    }

    let content: Content
    var isComparing = false
    var isLoupeEnabled = false
    var parameter: Parameter?
    var onCompare: (Bool) -> Void = { _ in }
    var previewReadout: Bool = false
    @State private var drag: FineDrag?
    @State private var transientLoupe: FilmCanvas.Loupe?
    @State private var savedLoupe = FilmCanvas.Loupe()

    private var loupe: FilmCanvas.Loupe? {
        transientLoupe ?? (isLoupeEnabled ? savedLoupe : nil)
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            Group {
                switch content {
                case let .photo(pixels, before, milliseconds):
                    FilmCanvas(image: isComparing ? before ?? pixels : pixels, loupe: loupe)
                        // Never inherit a crossfade from changes to the chrome.
                        .transaction { $0.animation = nil }
                        .aspectRatio(CGFloat(pixels.width) / CGFloat(pixels.height), contentMode: .fit)
                        .overlay {
                            CanvasGestureSurface(baseLoupe: isLoupeEnabled ? savedLoupe : nil,
                                                 onCompare: onCompare,
                                                 onDrag: { translation in fineDrag(translation, width: geometry.size.width) },
                                                 onLoupe: { value in
                                if let value { transientLoupe = value }
                                else {
                                    if isLoupeEnabled, let transientLoupe { savedLoupe = transientLoupe }
                                    transientLoupe = nil
                                }
                            })
                            .accessibilityHidden(true)
                        }
                        .overlay(alignment: .topLeading) {
                            if drag == nil && !previewReadout {
                                comparePill.padding(Tokens.Metrics.space10)
                            }
                        }
                        .overlay(alignment: .top) {
                            if let active = drag?.track.parameter ?? (previewReadout ? parameter : nil) {
                                CanvasReadoutPill(name: active.name, value: active.readout,
                                                  widthReference: drag?.widthReference ?? active.readout)
                                    .padding(.top, Tokens.Canvas.readoutTopInset)
                            }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if let milliseconds {
                                RenderTimePill(milliseconds: milliseconds)
                                    .opacity(isComparing ? 0 : 1)
                                    .padding(Tokens.Metrics.space10)
                            }
                        }
                case .empty, .loading:
                    emptyGate
                        .aspectRatio(Tokens.Canvas.gateAspectRatio, contentMode: .fit)
                        .padding(.horizontal, Tokens.Metrics.space16)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Tokens.Palette.canvas)
        .onChange(of: isLoupeEnabled) { savedLoupe = FilmCanvas.Loupe(); transientLoupe = nil }
        .onChange(of: parameter?.id) { drag = nil }
        .onDisappear { onCompare(false); drag = nil; transientLoupe = nil }
    }

    private struct FineDrag {
        let track: Scrubber.TrackMap
        let origin: CGFloat
        let widthReference: String

        init(track: Scrubber.TrackMap) {
            self.track = track
            origin = track.origin(of: track.parameter.value.wrappedValue)
            let parameter = track.parameter
            // SF Mono has equal advances. Reserve the longest formatted step,
            // including zero labels, detents and values outside the UI clamp.
            var candidates = [parameter.readout, parameter.format(parameter.range.upperBound)]
            for value in stride(from: parameter.range.lowerBound, through: parameter.range.upperBound, by: parameter.step) {
                candidates.append(parameter.format(value))
            }
            if let detent = parameter.detent { candidates.append(parameter.format(detent)) }
            widthReference = candidates.max { $0.count < $1.count } ?? parameter.readout
        }
    }

    private func fineDrag(_ translation: CGFloat?, width: CGFloat) {
        guard let translation else { drag = nil; return }
        guard let parameter else { return }
        if drag == nil {
            let track = parameter.control == .shutterDial
                ? Scrubber.TrackMap.shutterDial(for: parameter)
                : Scrubber.TrackMap(parameter: parameter, width: width)
            drag = FineDrag(track: track)
            Haptics.prepare()
        }
        guard let drag else { return }
        let direction: CGFloat = parameter.control == .shutterDial ? -1 : 1
        let outcome = drag.track.resolve(drag.origin + translation * Tokens.Canvas.dragGain * direction)
        let previous = parameter.value.wrappedValue
        guard outcome.value != previous else { return }
        parameter.value.wrappedValue = outcome.value
        let crossed = parameter.detent.map { (previous - $0) * (outcome.value - $0) < 0 } ?? false
        if (outcome.isAtDetent && !parameter.isAtDetent(previous)) || crossed { Haptics.detent() }
        else if outcome.isAtLimit && !drag.track.isAtLimit(previous) { Haptics.rangeLimit() }
        else { Haptics.step() }
    }

    private var comparePill: some View {
        Text(isComparing ? "Original" : "Hold to compare")
            .typeStyle(.comparePill)
            .foregroundStyle(isComparing ? Tokens.Canvas.originalText : Tokens.Canvas.compareText)
            .padding(.horizontal, Tokens.Metrics.space10)
            .frame(height: Tokens.Canvas.compareHeight)
            .background {
                RoundedRectangle(cornerRadius: Tokens.Canvas.compareRadius)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .overlay {
                        RoundedRectangle(cornerRadius: Tokens.Canvas.compareRadius)
                            .fill(isComparing ? Tokens.Palette.inkOnCanvas : Tokens.Canvas.pillFill)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Tokens.Canvas.compareRadius)
                    .strokeBorder(Tokens.Canvas.pillBorder, lineWidth: Tokens.Elevation.hairlineWidth)
            }
            .animation(Tokens.Motion.ease(Tokens.Motion.tick, reduceMotion: reduceMotion), value: isComparing)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var emptyGate: some View {
        ZStack {
            Canvas { context, size in
                var hatch = Path()
                let spacing = Tokens.Canvas.hatchWidth * 2
                for offset in stride(from: -size.height, through: size.width, by: spacing) {
                    hatch.move(to: CGPoint(x: offset, y: 0))
                    hatch.addLine(to: CGPoint(x: offset + size.height, y: size.height))
                }
                context.stroke(hatch, with: .color(Tokens.Canvas.hatch), lineWidth: Tokens.Canvas.hatchWidth)
            }
            VStack(spacing: Tokens.Canvas.gateTextGap) {
                Text(isLoading ? "Decoding…" : "Open a photo")
                    .typeStyle(.emptyTitle).foregroundStyle(Tokens.Palette.inkOnCanvas)
                if !isLoading {
                    Text("Choose a photo to begin.")
                        .typeStyle(.emptyCaption).foregroundStyle(Tokens.Canvas.emptyCaption)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Canvas.gateRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.Canvas.gateRadius)
                .strokeBorder(Tokens.Canvas.gateBorder, lineWidth: Tokens.Canvas.gateBorderWidth)
        }
    }

    private var isLoading: Bool {
        if case .loading = content { return true }
        return false
    }
}

private struct RenderTimePill: View {
    let milliseconds: Double
    @State private var isIdle = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("\(milliseconds, specifier: "%.0f") ms")
            .typeStyle(.renderTime).monospacedDigit()
            .foregroundStyle(Tokens.Canvas.renderText)
            .padding(.horizontal, Tokens.Canvas.renderPadding)
            .frame(height: Tokens.Canvas.renderHeight)
            .background {
                Capsule().fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .overlay(Capsule().fill(Tokens.Canvas.pillFill))
            }
            .overlay(Capsule().strokeBorder(Tokens.Canvas.pillBorder, lineWidth: Tokens.Elevation.hairlineWidth))
            .opacity(isIdle ? Tokens.Canvas.idleOpacity : 1)
            .allowsHitTesting(false)
            .task(id: milliseconds) {
                isIdle = false
                do { try await Task.sleep(for: .seconds(Tokens.Canvas.idleDelay)) }
                catch { return }
                withAnimation(Tokens.Motion.ease(Tokens.Motion.tick, reduceMotion: reduceMotion)) { isIdle = true }
            }
    }
}

#Preview("Canvas · empty") { CanvasView(content: .empty) }
#Preview("Canvas · decoding") { CanvasView(content: .loading) }

/// Screen 1k's transient readout; never intercepts the touch underneath it.
private struct CanvasReadoutPill: View {
    let name: String
    let value: String
    let widthReference: String

    var body: some View {
        HStack(spacing: Tokens.Canvas.readoutGap) {
            Text(name).typeStyle(.chipName).foregroundStyle(Tokens.Canvas.compareText)
            Text(widthReference).hidden()
                .overlay(alignment: .leading) { Text(value) }
                .typeStyle(.chipValue).monospacedDigit().foregroundStyle(Tokens.Canvas.readoutValue)
        }
        .lineLimit(1)
        .padding(.horizontal, Tokens.Metrics.space10)
        .frame(height: Tokens.Canvas.readoutHeight)
        .background {
            Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                .overlay(Capsule().fill(Tokens.Canvas.readoutFill))
        }
        .overlay(Capsule().strokeBorder(Tokens.Canvas.pillBorder, lineWidth: Tokens.Elevation.hairlineWidth))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A single recognizer owns arbitration. Separate SwiftUI gestures cannot observe
/// the second finger while also guaranteeing that an engaged compare stays locked.
private struct CanvasGestureSurface: UIViewRepresentable {
    var baseLoupe: FilmCanvas.Loupe?
    var onCompare: (Bool) -> Void
    var onDrag: (CGFloat?) -> Void
    var onLoupe: (FilmCanvas.Loupe?) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isMultipleTouchEnabled = true
        view.addGestureRecognizer(CanvasGestureRecognizer())
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        guard let gesture = view.gestureRecognizers?.first as? CanvasGestureRecognizer else { return }
        gesture.baseLoupe = baseLoupe
        gesture.onCompare = onCompare
        gesture.onDrag = onDrag
        gesture.onLoupe = onLoupe
    }

    static func dismantleUIView(_ view: UIView, coordinator: ()) {
        (view.gestureRecognizers?.first as? CanvasGestureRecognizer)?.cancelInteraction()
    }
}

private final class CanvasGestureRecognizer: UIGestureRecognizer {
    enum Mode { case waiting, pinchWaiting, compare, drag, loupe, ignored }
    var baseLoupe: FilmCanvas.Loupe?
    var onCompare: (Bool) -> Void = { _ in }
    var onDrag: (CGFloat?) -> Void = { _ in }
    var onLoupe: (FilmCanvas.Loupe?) -> Void = { _ in }
    private var mode = Mode.waiting
    private var fingers: Set<UITouch> = []
    private weak var compareTouch: UITouch?
    private var origin = CGPoint.zero
    private var pinchDistance: CGFloat = 0
    private var startingLoupe: FilmCanvas.Loupe?
    private var holdTask: Task<Void, Never>?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        fingers.formUnion(touches)
        guard mode == .waiting else { return }
        startingLoupe = baseLoupe
        if fingers.count > 1 {
            holdTask?.cancel()
            mode = .pinchWaiting
            origin = centroid
            pinchDistance = distance
        } else {
            origin = centroid
            holdTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(Tokens.Canvas.compareHoldDuration)) }
                catch { return }
                guard let self, self.mode == .waiting, self.fingers.count == 1 else { return }
                self.compareTouch = self.fingers.first
                self.mode = .compare
                self.state = .began
                self.onCompare(true)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        let point = centroid
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        switch mode {
        case .waiting:
            guard hypot(dx, dy) >= Tokens.Canvas.dragThreshold else { return }
            holdTask?.cancel()
            if startingLoupe != nil { mode = .loupe }
            else if abs(dx) >= abs(dy) { mode = .drag }
            else { mode = .ignored }
            state = .began
        case .pinchWaiting:
            guard abs(distance - pinchDistance) >= Tokens.Canvas.dragThreshold else { return }
            mode = .loupe
            state = .began
        case .compare, .ignored: return
        case .drag, .loupe: break
        }
        if mode == .drag {
            // Additional fingers cannot turn an already claimed drag into a pinch.
            guard fingers.count == 1 else { return }
            onDrag(dx)
        } else if mode == .loupe, let view, view.bounds.width > 0, view.bounds.height > 0 {
            onLoupe(FilmCanvas.Loupe(
                focus: startingLoupe?.focus ?? CGPoint(x: origin.x / view.bounds.width, y: origin.y / view.bounds.height),
                translation: CGSize(width: (startingLoupe?.translation.width ?? 0) + dx / view.bounds.width,
                                    height: (startingLoupe?.translation.height ?? 0) + dy / view.bounds.height)))
        }
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        fingers.subtract(touches)
        // An unrelated finger cannot release the initiating compare hold.
        if mode == .compare, let compareTouch, !touches.contains(compareTouch) { return }
        // The first lift ends inspection; remaining fingers never start a new mode.
        finish()
        mode = .ignored
        if fingers.isEmpty { state = state == .possible ? .failed : .ended }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        cancelInteraction()
    }

    func cancelInteraction() {
        finish()
        mode = .ignored
        fingers.removeAll()
        state = state == .possible ? .failed : .cancelled
    }

    override func reset() {
        super.reset()
        holdTask?.cancel()
        holdTask = nil
        fingers.removeAll()
        compareTouch = nil
        mode = .waiting
    }

    private func finish() {
        holdTask?.cancel()
        switch mode {
        case .compare: onCompare(false)
        case .drag: onDrag(nil)
        case .loupe: onLoupe(nil)
        default: break
        }
    }

    private var centroid: CGPoint {
        guard !fingers.isEmpty else { return origin }
        let sum = fingers.reduce(CGPoint.zero) { sum, touch in
            let point = touch.location(in: view)
            return CGPoint(x: sum.x + point.x, y: sum.y + point.y)
        }
        return CGPoint(x: sum.x / CGFloat(fingers.count), y: sum.y / CGFloat(fingers.count))
    }

    private var distance: CGFloat {
        let points = fingers.map { $0.location(in: view) }
        guard points.count == 2 else { return 0 }
        return hypot(points[0].x - points[1].x, points[0].y - points[1].y)
    }
}

#Preview("Canvas · fine drag readout") {
    CanvasReadoutPill(name: "Exposure", value: "+0.7 EV", widthReference: "+3.0 EV")
        .padding(Tokens.Metrics.space20).background(Tokens.Palette.canvas)
}
