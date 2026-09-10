import SwiftUI
import FilmEngine

/// The Catalogue is supplied in its bundled order. Pixels come from the editor's
/// existing thumbnail scheduler; a missing entry stays visibly developing.
struct Filmstrip: View {
    let catalogue: [Profile]
    let thumbnails: [String: RenderedPixels]
    @Binding var selectedStock: String
    let close: () -> Void
    @State private var atEnd = false
    @State private var startedAtEnd: Bool?
    @State private var viewportWidth: CGFloat = 0
    @Namespace private var selectionRing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var profiles: [Profile] { [.identity] + catalogue }
    var body: some View {
        VStack(spacing: Tokens.Filmstrip.footerGap) {
            strip
            HStack(spacing: Tokens.Metrics.space10) {
                HStack(spacing: 8) {
                    processLabel("C-41", .c41)
                    processLabel("ECN-2", .ecn2)
                    processLabel("E-6", .e6)
                    processLabel("B&W", .bwSilver)
                }
                Spacer(minLength: 0)
                Button { Haptics.buttonPress(); close() } label: {
                    Text("Controls").typeStyle(.filmControls)
                        .foregroundStyle(Tokens.Palette.textPrimary)
                        .padding(.horizontal, Tokens.Filmstrip.controlsPadding)
                        .frame(height: Tokens.Filmstrip.footerHeight)
                        .raisedSurface(cornerRadius: Tokens.Metrics.trackRadius)
                        .frame(height: Tokens.Metrics.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Returns to the parameter controls")
            }
            .padding(.horizontal, Tokens.Metrics.space16)
            .frame(height: Tokens.Filmstrip.footerHeight)
        }
        .frame(height: Tokens.Filmstrip.height)
    }

    private func processLabel(_ name: String, _ process: FilmProcess) -> some View {
        Text(name).font(.system(size: 9, design: .monospaced))
            .foregroundStyle(Tokens.Palette.process(process))
    }

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Tokens.Metrics.space10) {
                    ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                        cell(profile, index: index).id(profile.id)
                            .background {
                                if index == profiles.count - 1 {
                                    GeometryReader { proxy in
                                        Color.clear.preference(key: FilmstripEnd.self,
                                            value: proxy.frame(in: .named("filmstrip")).maxX)
                                    }
                                }
                            }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Stock filmstrip")
                .padding(.horizontal, Tokens.Metrics.space16)
                .padding(.top, Tokens.Metrics.space14)
                .padding(.bottom, Tokens.Metrics.space14)
            }
            .coordinateSpace(name: "filmstrip")
            .background(GeometryReader { geometry in
                Color.clear.onAppear { viewportWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { _, width in viewportWidth = width }
            })
            .onPreferenceChange(FilmstripEnd.self) { atEnd = $0 <= viewportWidth + 16 }
            .simultaneousGesture(DragGesture(minimumDistance: 12)
                .onChanged { change in
                    if startedAtEnd == nil { startedAtEnd = atEnd }
                    if atEnd && change.translation.width < -76 { close() }
                }
                .onEnded { change in
                    if startedAtEnd == true && change.translation.width < -32 { close() }
                    startedAtEnd = nil
                })
            .scrollIndicators(.hidden)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                        .init(color: .black, location: Tokens.Filmstrip.fadeStart),
                                        .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            .onAppear { proxy.scrollTo(selectedStock, anchor: .center) }
            .onChange(of: selectedStock) { proxy.scrollTo(selectedStock, anchor: .center) }
        }
        .frame(height: Tokens.Filmstrip.stripHeight)
        .background(Tokens.Filmstrip.base)
        .overlay(alignment: .top) { sprockets.padding(.top, Tokens.Filmstrip.rebateInset) }
        .overlay(alignment: .bottom) { sprockets.padding(.bottom, Tokens.Filmstrip.rebateInset) }
    }

    private func cell(_ profile: Profile, index: Int) -> some View {
        let selected = profile.id == selectedStock
        let approximation = profile.metadata.isApproximation ? ", approximation" : ""
        return Button {
            guard !selected else { return }
            Haptics.stockChange()
            // Do not put the model mutation in an animation transaction: the
            // canvas must publish its new render immediately, with no fade.
            selectedStock = profile.id
        } label: {
            VStack(alignment: .leading, spacing: Tokens.Metrics.space5) {
                thumbnail(profile, index: index)
                    .overlay {
                        if selected {
                            RoundedRectangle(cornerRadius: Tokens.Metrics.filmstripCellRadius)
                                .stroke(Tokens.Palette.accent, lineWidth: Tokens.Filmstrip.selectionRing * 2)
                                .background {
                                    RoundedRectangle(cornerRadius: Tokens.Metrics.filmstripCellRadius)
                                        .stroke(Tokens.Palette.deck, lineWidth: Tokens.Filmstrip.selectionHalo * 2)
                                }
                                .matchedGeometryEffect(id: "stock", in: selectionRing)
                                .allowsHitTesting(false)
                        }
                    }
                Text((profile.metadata.isApproximation ? "Approx. · " : "") + profile.metadata.displayName)
                    .typeStyle(.filmName)
                    .foregroundStyle(selected ? Tokens.Palette.accent : Tokens.Palette.textPrimary)
                    .lineLimit(1).truncationMode(.tail)
            }
            .frame(width: Tokens.Filmstrip.cellWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Tokens.Motion.ease(Tokens.Motion.tick, reduceMotion: reduceMotion), value: selectedStock)
        .accessibilityLabel(profile.metadata.displayName + approximation)
        .accessibilityValue(thumbnails[profile.id] == nil ? "developing" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func thumbnail(_ profile: Profile, index: Int) -> some View {
        ZStack(alignment: .bottom) {
            if let pixels = thumbnails[profile.id] {
                // FilmCanvas stretches to its bounds, so give it the input's
                // aspect ratio before cropping to the exposed frame.
                FilmCanvas(image: pixels)
                    .aspectRatio(CGFloat(pixels.width) / CGFloat(pixels.height), contentMode: .fill)
                    .frame(width: Tokens.Filmstrip.cellWidth, height: Tokens.Filmstrip.cellHeight)
                    .clipped()
            } else {
                DevelopingFrame()
            }
            if profile.id != "identity" {
                Tokens.Palette.process(profile.metadata.process).frame(height: Tokens.Filmstrip.processEdge)
            }
        }
        .frame(width: Tokens.Filmstrip.cellWidth, height: Tokens.Filmstrip.cellHeight)
        .overlay(alignment: .topLeading) {
            Text(String(format: "%02d", index)).typeStyle(.filmIndex)
                .foregroundStyle(Tokens.Filmstrip.indexInk)
                .shadow(color: Tokens.Filmstrip.indexShadow, radius: Tokens.Filmstrip.indexShadowRadius)
                .padding(.leading, Tokens.Metrics.space4)
                .padding(.top, Tokens.Filmstrip.rebateInset)
        }
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Metrics.filmstripCellRadius))
    }

    private var sprockets: some View {
        Canvas { context, size in
            for x in stride(from: Tokens.Metrics.space6, to: size.width, by: Tokens.Filmstrip.sprocketPitch) {
                context.fill(Path(CGRect(x: x, y: 0, width: Tokens.Filmstrip.sprocketWidth, height: size.height)),
                             with: .color(Tokens.Filmstrip.sprocket))
            }
        }
        .frame(height: Tokens.Filmstrip.rebateHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }


}

/// Real Catalogue and real rendered reference pixels; alternate entries remain
/// developing so both states can be inspected without racing a scheduler.
private struct FilmstripPreview: View {
    @State private var catalogue: [Profile] = []
    @State private var thumbnails: [String: RenderedPixels] = [:]
    @State private var selectedStock = "portra-400"
    @State private var error: String?

    var body: some View {
        VStack {
            Filmstrip(catalogue: catalogue, thumbnails: thumbnails, selectedStock: $selectedStock, close: {})
            if let error { Text(error).typeStyle(.caption) }
        }
        .background(Tokens.Palette.deck)
        .task {
            do {
                catalogue = try ProfileCatalogue.bundled().profiles
                let renderer = try Renderer()
                let reference = try ContactSheetReference.image()
                for (index, profile) in ([Profile.identity] + catalogue).enumerated() where index.isMultiple(of: 2) {
                    try Task.checkCancellation()
                    thumbnails[profile.id] = try await renderer.render(image: .linear(reference), profile: profile,
                                                                      settings: ContactSheetReference.settings)
                }
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}

#Preview("Stock filmstrip · Catalogue · rendered and developing") {
    FilmstripPreview().preferredColorScheme(.dark)
}

#Preview("Stock filmstrip · fixed deck · open and close") {
    DeckPreview(filmstripOpen: true).preferredColorScheme(.dark)
}

private struct FilmstripEnd: PreferenceKey {
    static let defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
