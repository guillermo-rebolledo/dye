import SwiftUI
import PhotosUI
import FilmEngine

/// Owns the Preview Render Path: one decoded screen-sized image, the current
/// settings, and a coalescing render loop so a slider drag renders the latest
/// values rather than every intermediate one.
@MainActor @Observable final class EditorModel {
    var catalogue: [Profile] = []
    var selectedStock = "identity" { didSet { stockChanged() } }
    var settings = RenderSettings() { didSet { scheduleRender() } }
    private(set) var pixels: RenderedPixels?
    private(set) var error: String?
    private(set) var isLoading = false
    private(set) var lastRenderMilliseconds: Double?

    static let previewMaximumDimension = 2048

    private var renderer: Renderer?
    private var preview: LinearImage?
    private var renderLoop: Task<Void, Never>?
    private var needsRender = false

    var profile: Profile { catalogue.first { $0.id == selectedStock } ?? .identity }
    var isIdentity: Bool { selectedStock == "identity" }

    /// The Profile this Stock derives from, when it models another's Emulsion.
    var derivedFrom: Profile? {
        guard let parent = profile.metadata.derivedFrom else { return nil }
        return catalogue.first { $0.id == parent }
    }

    /// Whether the Stock scatters at all; a Profile with no Halation has no control.
    var hasHalation: Bool { profile.metadata.halation.strength > 0 }

    /// How far the Stock scatters in its widest channel, in Film-Plane Microns.
    var halationReachMicrons: Double { profile.metadata.halation.radiusMicrons[0] }

    /// Whether the modelled taking lens diffuses at all.
    var hasBloom: Bool { profile.metadata.bloom.strength > 0 }

    /// How far the lens spreads what it diffuses, in Film-Plane Microns.
    var bloomRadiusMicrons: Double { profile.metadata.bloom.radiusMicrons }

    /// Whether the Stock grains at all; a Profile with no granularity has no control.
    var hasGrain: Bool { !profile.metadata.grain.isSilent }

    /// The crystal or dye-cloud radius the Stock grains at, in Film-Plane Microns.
    var grainRadiusMicrons: Double { profile.metadata.grain.grainRadiusMicrons }

    /// What one Preview pixel covers on the film, which is what decides whether the
    /// grain is resolved as texture or recorded as the fluctuation within a pixel.
    var previewPitchMicrons: Double? {
        guard let preview else { return nil }
        return profile.metadata.format.frameWidthMM * 1000 / Double(max(preview.width, preview.height))
    }

    /// Baked Development Offsets, or nil when the Stock has a single variant.
    var developmentRange: ClosedRange<Double>? {
        let stops = profile.metadata.colour.lutVariants.map(\.pushStops)
        guard let low = stops.min(), let high = stops.max(), low < high else { return nil }
        return low...high
    }

    func loadCatalogue() {
        do { catalogue = try ProfileCatalogue.bundled().profiles }
        catch { self.error = error.localizedDescription }
    }

    func open(_ item: PhotosPickerItem) async {
        isLoading = true
        defer { isLoading = false }
        do {
            error = nil
            if renderer == nil { renderer = try Renderer() }
            guard let data = try await item.loadTransferable(type: Data.self), let renderer else {
                throw FilmError.invalid("The photo could not be loaded")
            }
            let decoded = try await renderer.decode(data, maximumDimension: Self.previewMaximumDimension)
            try Task.checkCancellation()
            preview = decoded
            scheduleRender()
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }

    private func stockChanged() {
        if let range = developmentRange {
            settings.developmentOffset = min(max(settings.developmentOffset, range.lowerBound), range.upperBound)
        } else {
            settings.developmentOffset = 0
        }
        scheduleRender()
    }

    func scheduleRender() {
        needsRender = true
        guard renderLoop == nil, preview != nil, renderer != nil else { return }
        renderLoop = Task { [weak self] in
            defer { self?.renderLoop = nil }
            while let self, needsRender {
                needsRender = false
                guard let preview, let renderer else { return }
                let started = ContinuousClock.now
                do {
                    let result = try await renderer.render(image: .linear(preview), profile: profile, settings: settings)
                    pixels = result
                    error = nil
                    lastRenderMilliseconds = Double((ContinuousClock.now - started).components.attoseconds) / 1e15
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }
}
