import SwiftUI
import FilmEngine

/// A proof sheet, literally: every Profile in the Catalogue rendered against the
/// same fixed reference, printed on one dark paper with sprocket strips top and
/// bottom, and the Stock loaded in the editor marked in grease pencil.
///
/// Full screen and no deck, because you are not grading here — which is also why
/// the close is a single machined ×.
struct ContactSheetView: View {
    /// The Stock the editor has loaded, so the mark knows which frame to circle.
    let selectedStock: String
    @Environment(\.dismiss) private var dismiss
    @State private var profiles: [Profile] = []
    @State private var images: [String: RenderedPixels] = [:]
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Metrics.space14) {
            header
            ScrollView {
                ContactSheetPaper(profiles: profiles, images: images, selectedStock: selectedStock)
                if let error {
                    Text(error).typeStyle(.caption).foregroundStyle(Tokens.Palette.destructive)
                        .padding(.top, Tokens.Metrics.space10)
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, Tokens.ContactSheet.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Tokens.ContactSheet.backdrop.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task(load)
    }

    private var header: some View {
        HStack {
            // Accurate rather than decorative: `ContactSheetReference.settings`
            // pins the seed at 253.
            Text("Contact Sheet")
                .typeStyle(.contactHeader).foregroundStyle(Tokens.Palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: Tokens.Metrics.space10)
            Button { Haptics.buttonPress(); dismiss() } label: {
                Image(systemName: "xmark")
                    .font(Tokens.TypeStyle.sheetAction.font)
                    .foregroundStyle(Tokens.Palette.textSecondary)
                    .frame(width: Tokens.ContactSheet.closeDiameter, height: Tokens.ContactSheet.closeDiameter)
                    .raisedSurface(Circle(), face: .icon)
                    .frame(width: Tokens.Metrics.minimumHitTarget, height: Tokens.Metrics.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .frame(height: Tokens.ContactSheet.headerHeight)
    }

    /// The Catalogue renders here rather than in `EditorModel`: this is a fixed
    /// reference against every Profile, which has nothing to do with the photo the
    /// editor is holding.
    @Sendable private func load() async {
        do {
            profiles = try [.identity] + ProfileCatalogue.bundled().profiles
            let renderer = try Renderer()
            let input = try ContactSheetReference.image()
            for profile in profiles {
                try Task.checkCancellation()
                images[profile.id] = try await renderer.render(image: .linear(input), profile: profile,
                                                               settings: ContactSheetReference.settings)
            }
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
}

// MARK: - The paper

/// One dark paper with sprocket strips top and bottom, and a 3-up grid of 4:3
/// frames on it. Every frame it is given is drawn whether its render has arrived
/// or not, so a half-rendered sheet is a state this view has rather than one it
/// waits out.
struct ContactSheetPaper: View {
    let profiles: [Profile]
    let images: [String: RenderedPixels]
    let selectedStock: String

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Tokens.ContactSheet.columnGap),
              count: Tokens.ContactSheet.columns)
    }

    var body: some View {
        VStack(spacing: 0) {
            SprocketStrip().padding(.bottom, Tokens.ContactSheet.sprocketGap)
            LazyVGrid(columns: columns, spacing: Tokens.ContactSheet.rowGap) {
                ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                    frame(profile, index: index)
                }
                legend
            }
            .padding(.horizontal, Tokens.ContactSheet.paperPaddingHorizontal)
            SprocketStrip().padding(.top, Tokens.ContactSheet.sprocketGap)
        }
        .padding(.vertical, Tokens.ContactSheet.paperPaddingVertical)
        .background(Tokens.ContactSheet.paper)
        .overlay(Rectangle().strokeBorder(Tokens.ContactSheet.paperEdge,
                                          lineWidth: Tokens.Elevation.hairlineWidth))
    }

    private func frame(_ profile: Profile, index: Int) -> some View {
        let marked = profile.id == selectedStock
        return VStack(alignment: .leading, spacing: Tokens.ContactSheet.captionGap) {
            ZStack {
                if let image = images[profile.id] {
                    FilmCanvas(image: image)
                        .aspectRatio(CGFloat(image.width) / CGFloat(image.height), contentMode: .fill)
                } else {
                    DevelopingFrame()
                }
            }
            .aspectRatio(Tokens.ContactSheet.frameAspect, contentMode: .fit)
            .clipped()
            .overlay(Rectangle().strokeBorder(Tokens.ContactSheet.frameEdge,
                                              lineWidth: Tokens.Elevation.hairlineWidth))
            .overlay { if marked { SelectionMark() } }
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Metrics.space4) {
                Text(profile.metadata.displayName)
                    .typeStyle(.contactName).foregroundStyle(Tokens.Palette.textSecondary)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                Text(String(format: "%02d", index))
                    .typeStyle(.contactIndex)
                    .foregroundStyle(profile.id == Profile.identity.id
                                     ? Tokens.Palette.textTertiary
                                     : Tokens.Palette.process(profile.metadata.process))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(profile.metadata.displayName)
        .accessibilityValue(images[profile.id] == nil ? "developing" : "")
        .accessibilityAddTraits(marked ? .isSelected : [])
    }

    /// What the sheet is, in the margin, where a printed proof sheet says it. The
    /// size is read off a render rather than asserted, so it cannot go stale.
    private var legend: some View {
        let processes = Set(profiles.filter { $0.id != Profile.identity.id }.map(\.metadata.process)).count
        return Text("\(profiles.count) stocks · \(processes) processes")
            .typeStyle(.contactFooter)
            .foregroundStyle(Tokens.Palette.textDisabled)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}

// MARK: - The mark

/// The one decorative element in the app, and it survives because it is doing a
/// job: it says which of sixteen frames is the one on screen.
///
/// Drawn as a hand-drawn stroke rather than a geometric ring. A perfect circle
/// would read as a selection state — something the app did — where an overshot,
/// wandering line reads as a mark someone made.
private struct SelectionMark: View {
    var body: some View {
        ZStack {
            Image(systemName: "checkmark")
                .typeStyle(.greasePencil)
                .foregroundStyle(Tokens.Palette.accent)
                .padding(Tokens.ContactSheet.labelGap)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Paper

/// The rebate a strip of film is cut from, top and bottom of the paper.
private struct SprocketStrip: View {
    var body: some View {
        Canvas { context, size in
            for x in stride(from: Tokens.ContactSheet.sprocketGap, to: size.width,
                            by: Tokens.ContactSheet.sprocketPitch) {
                context.fill(Path(CGRect(x: x, y: 0, width: Tokens.ContactSheet.sprocketWidth,
                                         height: size.height)),
                             with: .color(Tokens.Filmstrip.sprocket))
            }
        }
        .frame(height: Tokens.ContactSheet.sprocketHeight)
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

/// The full sheet, loading the Catalogue and rendering it exactly as the app does.
#Preview("Contact sheet · marked Stock") {
    ContactSheetView(selectedStock: "portra-400").preferredColorScheme(.dark)
}

/// Half the Catalogue rendered and the rest still developing, so both treatments
/// are visible at once without racing the render loop.
private struct PartialContactSheet: View {
    @State private var profiles: [Profile] = []
    @State private var images: [String: RenderedPixels] = [:]

    var body: some View {
        ScrollView {
            ContactSheetPaper(profiles: profiles, images: images, selectedStock: "velvia-50")
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, Tokens.ContactSheet.screenPadding)
        .background(Tokens.ContactSheet.backdrop.ignoresSafeArea())
        .task {
            guard let catalogue = try? ProfileCatalogue.bundled().profiles,
                  let renderer = try? Renderer(), let input = try? ContactSheetReference.image() else { return }
            profiles = [.identity] + catalogue
            for (index, profile) in profiles.enumerated() where index.isMultiple(of: 2) {
                images[profile.id] = try? await renderer.render(image: .linear(input), profile: profile,
                                                                settings: ContactSheetReference.settings)
            }
        }
    }
}

#Preview("Contact sheet · rendering") {
    PartialContactSheet().preferredColorScheme(.dark)
}
