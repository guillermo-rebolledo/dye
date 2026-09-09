import SwiftUI
import FilmEngine

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            Group {
                switch content {
                case let .photo(pixels, before, milliseconds):
                    FilmCanvas(image: isComparing ? before ?? pixels : pixels)
                        // Never inherit a crossfade from changes to the chrome.
                        .transaction { $0.animation = nil }
                        .aspectRatio(CGFloat(pixels.width) / CGFloat(pixels.height), contentMode: .fit)
                        .overlay(alignment: .topLeading) { comparePill.padding(Tokens.Metrics.space10) }
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
