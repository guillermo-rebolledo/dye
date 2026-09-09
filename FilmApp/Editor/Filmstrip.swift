import SwiftUI
import FilmEngine

/// The Catalogue is supplied in its bundled order. Pixels come from the editor's
/// existing thumbnail scheduler; a missing entry stays visibly developing.
struct Filmstrip: View {
    let catalogue: [Profile]
    let thumbnails: [String: RenderedPixels]
    @Binding var selectedStock: String
    let close: () -> Void
    @Namespace private var selectionRing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var profiles: [Profile] { [.identity] + catalogue }
    private var selectedProfile: Profile { profiles.first { $0.id == selectedStock } ?? .identity }

    private var provenance: String? {
        guard let parentID = selectedProfile.metadata.derivedFrom else { return nil }
        let parent = catalogue.first { $0.id == parentID }?.metadata.displayName ?? parentID
        if selectedProfile.id == "cinestill-800t" {
            return "The same emulsion as \(parent), modelled without its remjet backing."
        }
        return "Derived from \(parent)."
    }

    var body: some View {
        VStack(spacing: Tokens.Filmstrip.footerGap) {
            strip
            HStack(spacing: Tokens.Metrics.space10) {
                if let provenance {
                    Text(provenance).typeStyle(.filmProvenance)
                        .foregroundStyle(Tokens.Deck.captionInk)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(provenance)
                } else {
                    legend
                }
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

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Tokens.Metrics.space10) {
                    ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                        cell(profile, index: index).id(profile.id)
                    }
                }
                .padding(.horizontal, Tokens.Metrics.space16)
                .padding(.top, Tokens.Metrics.space14)
                .padding(.bottom, Tokens.Metrics.space14)
            }
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stock filmstrip")
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
                Text(profile.metadata.displayName).typeStyle(.filmName)
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
                developing
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

    private var developing: some View {
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
            Text("developing…").typeStyle(.filmIndex).foregroundStyle(Tokens.Deck.captionInk)
                .padding(.bottom, Tokens.Filmstrip.developingInset)
        }
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

    private var legend: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Tokens.Metrics.space10) {
                ForEach(FilmProcess.allCases, id: \.self) { process in
                    HStack(spacing: Tokens.Metrics.space4) {
                        Circle().fill(Tokens.Palette.process(process))
                            .frame(width: Tokens.Metrics.space6, height: Tokens.Metrics.space6)
                        Text(process.rawValue.uppercased()).typeStyle(.filmLegend)
                            .foregroundStyle(Tokens.Deck.captionInk)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(process.displayName)
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Process legend")
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
