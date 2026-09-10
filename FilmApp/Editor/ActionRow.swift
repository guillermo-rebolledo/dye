import SwiftUI
import PhotosUI

struct ActionRow: View {
    @Binding var photo: PhotosPickerItem?
    let hasPhoto: Bool
    let canExport: Bool
    let showPresets: () -> Void
    let showContactSheet: () -> Void
    let showExport: () -> Void
    @Binding var isLoupeEnabled: Bool

    @State private var selectedAction = "Photo"
    @State private var showsPhotoPicker = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace

    @ViewBuilder var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer { bar }
        } else { bar }
    }

    private var bar: some View {
        HStack(spacing: Tokens.Metrics.space5) {
            PhotosPicker(selection: $photo, matching: .images, preferredItemEncoding: .current) {
                DeckActionLabel(name: "Photo", symbol: "photo")
            }
            .background { selectionLens("Photo") }
            .help("Photo")
            .contextMenu {
                Button("Choose photo", systemImage: "photo") { select("Photo"); showsPhotoPicker = true }
            }
            Button { select("Presets"); showPresets() } label: {
                actionLabel("Presets", "slider.horizontal.3", enabled: hasPhoto)
            }
            .disabled(!hasPhoto)
            .contextMenu { Button("Presets", action: showPresets) }
            Button { select("Contact Sheet"); showContactSheet() } label: {
                actionLabel("Contact Sheet", "square.grid.3x3")
            }
            .contextMenu {
                Button("Contact Sheet", action: showContactSheet)
                Toggle("Loupe", isOn: $isLoupeEnabled).disabled(!hasPhoto)
            }
            Button { select("Export"); showExport() } label: {
                actionLabel("Export", "square.and.arrow.up", enabled: hasPhoto && canExport)
            }
            .disabled(!hasPhoto || !canExport)
            .contextMenu { Button("Export", action: showExport) }
        }
        .buttonStyle(DeckActionPress())
        .frame(height: Tokens.Deck.actionHeight)
        .modifier(EditorGlass())
        .onChange(of: photo) { select("Photo") }
        .photosPicker(isPresented: $showsPhotoPicker, selection: $photo, matching: .images, preferredItemEncoding: .current)
    }

    private func actionLabel(_ name: String, _ symbol: String, enabled: Bool = true) -> some View {
        DeckActionLabel(name: name, symbol: symbol, enabled: enabled)
            .background { if enabled { selectionLens(name) } }
            .help(name)
    }

    @ViewBuilder private func selectionLens(_ name: String) -> some View {
        if selectedAction == name {
            if #available(iOS 26.0, *), !reduceTransparency {
                Capsule().fill(.clear).frame(width: 52, height: 40)
                    .glassEffect(.regular, in: .capsule)
                    .glassEffectID("selected-action", in: glassNamespace)
            } else {
                Capsule().fill(.white.opacity(0.12)).frame(width: 52, height: 40)
            }
        }
    }

    private func select(_ name: String) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { selectedAction = name }
    }

}

private struct DeckActionLabel: View {
    let name: String
    let symbol: String
    var enabled = true

    var body: some View {
        VStack(spacing: Tokens.Metrics.space4) {
            Image(systemName: symbol).font(.system(size: 20))
                .foregroundStyle(Tokens.Palette.textPrimary)
                .frame(width: Tokens.Deck.actionIconWidth, height: Tokens.Deck.actionIconHeight)

        }
        .opacity(enabled ? 1 : Tokens.Deck.unavailableOpacity)
        .frame(maxWidth: .infinity)
        .frame(height: Tokens.Metrics.minimumHitTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }
}

private struct DeckActionPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .background(configuration.isPressed ? .white.opacity(0.12) : .clear, in: Capsule())
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.buttonPress() }
            }
    }
}

#Preview("Actions · photo loaded and empty") {
    VStack(spacing: Tokens.Metrics.space20) {
        ActionRow(photo: .constant(nil), hasPhoto: true, canExport: true,
                  showPresets: {}, showContactSheet: {}, showExport: {}, isLoupeEnabled: .constant(false))
        ActionRow(photo: .constant(nil), hasPhoto: false, canExport: false,
                  showPresets: {}, showContactSheet: {}, showExport: {}, isLoupeEnabled: .constant(false))
    }
    .padding(Tokens.Metrics.space16).background(Tokens.Palette.deck).preferredColorScheme(.dark)
}
