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

    var body: some View {
        HStack(spacing: Tokens.Metrics.space5) {
            PhotosPicker(selection: $photo, matching: .images, preferredItemEncoding: .current) {
                DeckActionLabel(name: "Photo", symbol: "photo", primary: !hasPhoto)
            }
            Button(action: showPresets) {
                DeckActionLabel(name: "Presets", symbol: "slider.horizontal.3", enabled: hasPhoto)
            }
            .disabled(!hasPhoto)
            Button(action: showContactSheet) {
                DeckActionLabel(name: "Contact Sheet", symbol: "square.grid.3x3")
            }
            .contextMenu {
                Toggle("Loupe", isOn: $isLoupeEnabled).disabled(!hasPhoto)
            }
            Button(action: showExport) {
                DeckActionLabel(name: "Export", symbol: "square.and.arrow.up", enabled: hasPhoto && canExport)
            }
            .disabled(!hasPhoto || !canExport)
        }
        .buttonStyle(DeckActionPress())
        .frame(height: Tokens.Deck.actionHeight)
    }

}

private struct DeckActionLabel: View {
    let name: String
    let symbol: String
    var enabled = true
    var primary = false

    var body: some View {
        VStack(spacing: Tokens.Metrics.space4) {
            Image(systemName: symbol).font(Tokens.TypeStyle.controlName.font)
                .foregroundStyle(primary ? Tokens.Palette.accent : Tokens.Palette.textPrimary)
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
            .offset(y: configuration.isPressed ? Tokens.Motion.pressDepth : 0)
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
