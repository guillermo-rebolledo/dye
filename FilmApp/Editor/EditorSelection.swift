import SwiftUI

/// What the deck is showing: which stage, which parameter inside it, and whether
/// the filmstrip has taken the parameter row's place.
///
/// This is presentation state and deliberately does not live on `EditorModel`.
/// The model owns the render loop — the decoded photo, the settings and the
/// coalescing that keeps a drag rendering the latest values — and has no notion
/// of a selected stage or an active control. Giving it one would put a tap on the
/// same object as a render, and every one of these changes is free where a
/// settings change costs a frame.
@MainActor @Observable final class EditorSelection {
    /// Light, then Film, then Lab: left to right is the order light travels.
    var stage: EditorStage = .light

    /// The parameter the active control is drawing, or nil before the first
    /// reconcile — no Stock is loaded and no stage has anything to offer yet.
    private(set) var activeParameter: Parameter.Identity?

    /// Whether the filmstrip has replaced the parameter row and active control.
    var isFilmstripOpen = false

    /// Moves to a stage. The active parameter is not carried across, because it
    /// belongs to the stage that offered it; `reconcile(with:)` picks the new one.
    func select(_ stage: EditorStage) {
        guard stage != self.stage else { return }
        self.stage = stage
        activeParameter = nil
        isFilmstripOpen = false
    }

    /// Makes a parameter the active control. The filmstrip closes: it occupies the
    /// space the active control draws in, so the two are never both on screen.
    func select(_ parameter: Parameter.Identity) {
        activeParameter = parameter
        isFilmstripOpen = false
    }

    /// Points the selection at something the Stock on screen actually offers.
    ///
    /// Glass and Print do not survive a change of Stock, and neither does a
    /// selection. A Stock with no Halation offers no Halation parameter, so a
    /// selection left pointing at one would draw an active control for a value
    /// nothing renders. Call this whenever the list is rebuilt; it keeps the
    /// selection when it is still on offer and falls back to the first parameter
    /// when it is not.
    func reconcile(with parameters: [Parameter]) {
        guard !parameters.isEmpty else {
            activeParameter = nil
            return
        }
        if let activeParameter, parameters.contains(where: { $0.id == activeParameter }) { return }
        activeParameter = parameters[0].id
    }

    /// The parameter the active control should draw, resolved against the list the
    /// Stock offers rather than trusted from the identity alone.
    func activeParameter(in parameters: [Parameter]) -> Parameter? {
        guard let activeParameter else { return parameters.first }
        return parameters.first { $0.id == activeParameter } ?? parameters.first
    }
}

// MARK: - Preview

/// The selection driving a plain list of what the deck would draw: switching
/// stage moves the active parameter with it, and a Stock that hides the active
/// parameter hands the selection to the first one it does offer.
private struct SelectionCatalogue: View {
    @State private var model = EditorModel()
    @State private var selection = EditorSelection()
    private let stocks = ["identity", "tri-x-400", "velvia-50", "portra-400"]

    var body: some View {
        let parameters = model.parameters(for: selection.stage)
        VStack(alignment: .leading, spacing: 16) {
            Picker("Stock", selection: $model.selectedStock) {
                ForEach(stocks, id: \.self) { Text($0) }
            }
            .pickerStyle(.menu)
            Picker("Stage", selection: Binding(get: { selection.stage }, set: { selection.select($0) })) {
                ForEach(EditorStage.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack(spacing: 5) {
                ForEach(parameters) { parameter in
                    Button(parameter.name) { selection.select(parameter.id) }
                        .buttonStyle(.bordered)
                        .tint(selection.activeParameter == parameter.id ? .accentColor : .gray)
                }
            }
            if let active = selection.activeParameter(in: parameters) {
                Text("Active: \(active.name) — \(active.readout)").font(.headline.monospacedDigit())
            } else {
                Text("Nothing to show").foregroundStyle(.secondary)
            }
            Toggle("Filmstrip open", isOn: Binding(get: { selection.isFilmstripOpen },
                                                   set: { selection.isFilmstripOpen = $0 }))
            Spacer()
        }
        .padding()
        .task { model.loadCatalogue() }
        .onChange(of: model.selectedStock) { selection.reconcile(with: model.parameters(for: selection.stage)) }
        .onChange(of: selection.stage) { selection.reconcile(with: model.parameters(for: selection.stage)) }
    }
}

#Preview("Editor selection") {
    SelectionCatalogue()
}
