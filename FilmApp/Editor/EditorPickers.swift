import SwiftUI

/// Compact selectors above the canvas; detailed stock previews live in the sheet.
struct EditorPickers: View {
    let model: EditorModel
    let selection: EditorSelection
    let hasPhoto: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                stockPicker
                outputPicker
            }
            VStack(alignment: .leading, spacing: 10) {
                stockPicker
                outputPicker
            }
        }
        .foregroundStyle(Tokens.Palette.textPrimary)
        .buttonStyle(.plain)
        .disabled(!hasPhoto)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity)
        .sheet(isPresented: Binding(get: { selection.isFilmstripOpen }, set: { selection.isFilmstripOpen = $0 })) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Stock").font(.title2.bold())
                Text(model.profile.metadata.displayName).font(.headline)
                Filmstrip(catalogue: model.catalogue, thumbnails: model.thumbnails,
                          selectedStock: Binding(get: { model.selectedStock }, set: { model.selectedStock = $0 }),
                          close: { selection.isFilmstripOpen = false })
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 16)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Tokens.Palette.deck)
        }
        .sheet(isPresented: Binding(get: { selection.isOutputBrowserOpen }, set: { selection.isOutputBrowserOpen = $0 })) {
            VStack(spacing: 24) {
                Text("Output").font(.title2.bold())
                OutputStageCards(model: model)
                Button("Done") { selection.isOutputBrowserOpen = false }
                    .frame(minHeight: 44)
            }
            .padding(24)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Tokens.Palette.deck)
        }
    }

    private var stockPicker: some View {
        Button { selection.isFilmstripOpen = true } label: {
            pickerLabel(model.profile.metadata.displayName)
        }
        .accessibilityLabel("Stock")
        .accessibilityValue(model.profile.metadata.displayName)
        .accessibilityHint("Browse stocks")
    }

    @ViewBuilder private var outputPicker: some View {
        if !model.outputStages.isEmpty {
            Button { selection.isOutputBrowserOpen = true } label: {
                pickerLabel(model.outputStage.displayName)
            }
            .accessibilityLabel("Output")
            .accessibilityValue(model.outputStage.displayName)
            .accessibilityHint("Browse output options")
        }
    }

    private func pickerLabel(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .contentShape(Capsule())
        .modifier(EditorGlass())
    }
}
