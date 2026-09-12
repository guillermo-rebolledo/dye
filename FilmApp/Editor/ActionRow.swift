import SwiftUI

/// Editing commands share one glass surface. They present transient tools, so
/// they don't retain a tab-style selection after a tool is dismissed.
struct ActionRow: View {
    @Binding var photo: PickedPhoto?
    let hasPhoto: Bool
    let canExport: Bool
    let showPresets: () -> Void
    let showContactSheet: () -> Void
    let showExport: () -> Void
    @Binding var isLoupeEnabled: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 12) {
                    photoPicker
                    Menu {
                        Button("Presets", systemImage: "slider.horizontal.3", action: showPresets)
                            .disabled(!hasPhoto)
                        Button("Stock reference", systemImage: "square.grid.3x3", action: showContactSheet)
                        Toggle("Preview zoom", systemImage: "magnifyingglass", isOn: $isLoupeEnabled)
                            .disabled(!hasPhoto)
                        Button("Export", systemImage: "square.and.arrow.up", action: showExport)
                            .disabled(!hasPhoto || !canExport)
                    } label: {
                        DeckActionLabel(name: "More", symbol: "ellipsis")
                    }
                    .accessibilityHint("Presets, Stock reference, Preview zoom, and Export")
                }
                .buttonStyle(DeckActionPress())
            } else {
                actions
            }
        }
        .padding(6)
        .modifier(EditorGlass())
        .accessibilityIdentifier("photo-tools")
    }

    private var photoPicker: some View {
        SinglePhotoPicker(selection: $photo) {
            DeckActionLabel(name: "Photo", symbol: "photo")
        }
        .accessibilityHint("Choose a photo from your library")
    }

    private var actions: some View {
        HStack(spacing: 0) {
            photoPicker

            Button(action: showPresets) {
                DeckActionLabel(name: "Presets", symbol: "slider.horizontal.3")
            }
            .disabled(!hasPhoto)

            Button(action: showContactSheet) {
                DeckActionLabel(name: "Stock reference", symbol: "square.grid.3x3")
            }
            .accessibilityHint("Compares stocks on a sample image. Touch and hold for Preview zoom.")
            .contextMenu {
                Button("Stock reference", action: showContactSheet)
                Toggle("Preview zoom", isOn: $isLoupeEnabled).disabled(!hasPhoto)
            }

            Button(action: showExport) {
                DeckActionLabel(name: "Export", symbol: "square.and.arrow.up")
            }
            .disabled(!hasPhoto || !canExport)
        }
        .buttonStyle(DeckActionPress())
    }
}

private struct DeckActionLabel: View {
    let name: String
    let symbol: String
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .caption2) private var labelLineHeight: CGFloat = 14

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .regular))
                .frame(height: 25)
            Text(name)
                .font(.caption2.weight(.medium))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(isEnabled ? Tokens.Palette.textPrimary : Tokens.Palette.textDisabled)
        .padding(.horizontal, 4)
        .frame(minWidth: 64, maxWidth: .infinity)
        .frame(minHeight: max(56, labelLineHeight + 40))
        .contentShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }
}

private struct DeckActionPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? .white.opacity(0.12) : .clear, in: Capsule())
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

#Preview("Actions · largest text") {
    ActionRow(photo: .constant(nil), hasPhoto: true, canExport: true,
              showPresets: {}, showContactSheet: {}, showExport: {}, isLoupeEnabled: .constant(false))
        .dynamicTypeSize(.accessibility5)
        .padding().background(Tokens.Palette.deck).preferredColorScheme(.dark)
}
