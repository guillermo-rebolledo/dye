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
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity)
        .sheet(isPresented: Binding(get: { selection.isFilmstripOpen }, set: { selection.isFilmstripOpen = $0 })) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Film Stock").font(.title2.bold())
                Text(model.profile.metadata.qualifiedDisplayName).font(.headline)
                // The qualifiers only mean anything if the sheet says what they are,
                // and this is the one screen where every name is on show at once.
                Text(Legal.qualifierExplanation)
                    .font(.footnote)
                    .foregroundStyle(Tokens.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Filmstrip(catalogue: model.catalogue, thumbnails: model.thumbnails,
                          selectedStock: Binding(get: { model.selectedStock }, set: { model.selectedStock = $0 }),
                          close: { selection.isFilmstripOpen = false })
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 16)
            // The Catalogue sweep renders eighteen Profiles and reads about 54MB of
            // Colour Cube. It runs while this sheet is up and not otherwise.
            .onAppear { model.isCatalogueVisible = true }
            .onDisappear { model.isCatalogueVisible = false }
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
            pickerLabel(model.isIdentity ? "Film Stock" : model.profile.metadata.qualifiedDisplayName)
        }
        .accessibilityLabel("Film Stock")
        .accessibilityValue(model.profile.metadata.spokenDisplayName)
        .accessibilityHint("Choose a film stock")
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
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .truncationMode(.tail)
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
