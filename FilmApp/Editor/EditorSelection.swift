import SwiftUI

/// Presentation state follows one ordered pipeline. Identity is retained when a
/// stock changes the available list; the index is reconciled before navigation.
@MainActor @Observable final class EditorSelection {
    private(set) var railIndex = 0
    private(set) var activeParameter: Parameter.Identity?
    private var parameters: [Parameter] = []
    var stage: EditorStage { parameters.first { $0.id == activeParameter }?.stage ?? .adjust }
    // Browsing never changes the dial selection or its scroll position.
    var isFilmstripOpen = false
    var isOutputBrowserOpen = false

    func select(_ stage: EditorStage) {
        guard let parameter = parameters.first(where: { $0.stage == stage }) else { return }
        select(parameter.id)
    }

    func select(_ identity: Parameter.Identity) {
        guard let index = parameters.firstIndex(where: { $0.id == identity }) else { return }
        let oldStage = stage
        let changed = activeParameter != identity
        railIndex = index
        activeParameter = identity
        if changed {
            if oldStage != stage { Haptics.thresholdCrossing() }
            else { Haptics.step() }
        }
    }

    func move(_ offset: Int) {
        guard !parameters.isEmpty else { return }
        let index = min(max(railIndex + offset, 0), parameters.count - 1)
        select(parameters[index].id)
    }

    func reconcile(with parameters: [Parameter]) {
        let parameters = parameters.filter { $0.id != .stock && $0.id != .outputStage }
        self.parameters = parameters
        if let index = parameters.firstIndex(where: { $0.id == activeParameter }) {
            railIndex = index
        } else {
            railIndex = min(railIndex, max(parameters.count - 1, 0))
            activeParameter = parameters.isEmpty ? nil : parameters[railIndex].id
        }
    }

    func activeParameter(in parameters: [Parameter]) -> Parameter? {
        parameters.first { $0.id == activeParameter } ?? parameters.first { $0.id != .stock && $0.id != .outputStage }
    }
}
