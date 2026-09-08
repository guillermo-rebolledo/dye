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
    /// The photo as it arrived. The Preview is a screen-sized decode of it, but an
    /// Export has to start from the full-resolution original, so the bytes are kept.
    private var original: Data?
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
            original = data
            export = nil
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

    // MARK: - Export

    /// Where a full-resolution Export has got to. One at a time: the Export path sizes
    /// its Tiles to a memory budget, and two running at once would blow it.
    enum Export {
        case running(ExportProgress)
        case finished(URL)
        case failed(String)
    }

    private(set) var export: Export?
    var canExport: Bool { original != nil && exportTask == nil }
    var isExporting: Bool { if case .running = export { true } else { false } }
    var exportFormat: ExportFormat = .heif
    var exportOutput: RenderSettings.Output = .displayP3
    private var exportTask: Task<Void, Never>?

    /// The device's own thermal state, watched rather than sampled once, so a long
    /// Export can say why it slowed down while it is still running.
    private(set) var thermalState = ProcessInfo.processInfo.thermalState

    /// What the Export will actually render Grain with. At `.serious` the system is
    /// already throttling, so the Stock's own model gives way to the cheap one.
    var exportGrainModel: GrainModel {
        Renderer.grainModel(profile, path: .export, thermalState: thermalState)
    }
    var isThrottled: Bool { thermalState == .serious || thermalState == .critical }

    func watchThermalState() async {
        let observer = ThermalObserver()
        for await state in observer.states { thermalState = state }
    }

    /// Renders the photo at full resolution and writes it as a file to share. The
    /// renderer reports per Tile, which is also where it can be cancelled.
    func exportImage() {
        guard let original, let renderer, exportTask == nil else { return }
        let (profile, settings, format) = (profile, exportSettings, exportFormat)
        export = .running(ExportProgress(completedTiles: 0, tileCount: 0))
        // The renderer reports from its own executor, so each Tile hops back here.
        let report: @Sendable (ExportProgress) -> Void = { [weak self] progress in
            Task { @MainActor in
                guard let self, self.isExporting else { return }
                self.export = .running(progress)
            }
        }
        exportTask = Task { [weak self] in
            defer { self?.exportTask = nil }
            do {
                let data = try await renderer.export(image: .encoded(original), profile: profile, settings: settings,
                                                     format: format, progress: report)
                try Task.checkCancellation()
                self?.export = .finished(try Self.write(data, named: "\(profile.id).\(format.fileExtension)"))
            } catch is CancellationError {
                self?.export = nil
            } catch {
                self?.export = .failed(error.localizedDescription)
            }
        }
    }

    /// The colour half of the same look as a `.cube` file. It is a lattice render
    /// rather than a frame, so it is quick enough not to need progress or cancelling.
    func exportLUT() {
        guard let renderer, exportTask == nil else { return }
        let (profile, settings) = (profile, exportSettings)
        export = .running(ExportProgress(completedTiles: 0, tileCount: 1))
        exportTask = Task { [weak self] in
            defer { self?.exportTask = nil }
            do {
                let text = try await renderer.exportedLUT(profile: profile, settings: settings)
                self?.export = .finished(try Self.write(Data(text.utf8), named: "\(profile.id).cube"))
            } catch {
                self?.export = .failed(error.localizedDescription)
            }
        }
    }

    func cancelExport() {
        exportTask?.cancel()
        export = nil
    }

    func dismissExport() {
        if case .running = export { return }
        export = nil
    }

    /// The Preview's settings with the chosen delivery encoding. Everything else about
    /// the render is what is on screen, which is the point of sharing the shaders.
    private var exportSettings: RenderSettings {
        var settings = settings
        settings.output = exportOutput
        return settings
    }

    private static func write(_ data: Data, named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
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

/// The device's thermal state as an async sequence.
///
/// `NotificationCenter.notifications(named:)` would be the obvious way to write this,
/// but the `Notification` it yields is not `Sendable` on every SDK the project builds
/// against. The payload is not wanted anyway — the state is read back from
/// `ProcessInfo` — so the observer yields the state itself and the notification never
/// crosses an isolation boundary. The token lives as long as the stream does.
private final class ThermalObserver: @unchecked Sendable {
    let states: AsyncStream<ProcessInfo.ThermalState>
    private let token: any NSObjectProtocol

    init() {
        let (states, continuation) = AsyncStream<ProcessInfo.ThermalState>.makeStream()
        self.states = states
        token = NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                                                       object: nil, queue: .main) { _ in
            continuation.yield(ProcessInfo.processInfo.thermalState)
        }
    }

    deinit { NotificationCenter.default.removeObserver(token) }
}
