import SwiftUI
import PhotosUI
import Photos
import ImageIO
import os
import SwiftData
import FilmEngine

/// Owns the Preview Render Path: one decoded screen-sized image, the current
/// settings, and a coalescing render loop so a slider drag renders the latest
/// values rather than every intermediate one.
@MainActor @Observable final class EditorModel {
    var catalogue: [Profile] = []
    var selectedStock = "identity" { didSet { stockChanged() } }
    var settings = RenderSettings() { didSet { scheduleRender() } }
    private(set) var pixels: RenderedPixels?
    private(set) var beforePixels: RenderedPixels?
    private(set) var thumbnails: [String: RenderedPixels] = [:]
    private var thumbnailInput: LinearImage?
    private var thumbnailTask: Task<Void, Never>?
    private var imageGeneration = UUID()
    private(set) var error: String?
    private(set) var isLoading = false
    private(set) var lastRenderMilliseconds: Double?

    static let previewMaximumDimension = 2048

    private var renderer: Renderer?
    private var preview: LinearImage?
    /// The photo as it arrived. The Preview is a screen-sized decode of it, but an
    /// Export has to start from the full-resolution original, so the bytes are kept.
    private var original: Data?
    private(set) var originalDate: Date?
    private var renderLoop: Task<Void, Never>?
    private var needsRender = false

    /// The Adjustments the editor is holding at zero, each with the value it held
    /// when it was switched off. A photo editor lets a control be taken out of the
    /// picture without being thrown away, which a reset cannot do, and the two are
    /// different questions: *what would this look like without it* and *I do not
    /// want it*. Only the editor knows the difference. Everything downstream — the
    /// render, the Export, a saved Preset — sees the zero in `settings`, because a
    /// bypassed control really is not applied.
    var stashedAdjustments: [Parameter.Identity: Double] = [:]

    var profile: Profile { catalogue.first { $0.id == selectedStock } ?? .identity }

    /// The Catalogue as every surface that renders it shows it: the Identity Profile
    /// first, then the bundled order. Identity is not a Stock and is not in the
    /// Catalogue, but it is a cell in the filmstrip, a row on the contact sheet and a
    /// Preset a photograph can be saved at.
    var catalogueWithIdentity: [Profile] { [.identity] + catalogue }
    var isIdentity: Bool { selectedStock == "identity" }

    /// The Profile this Stock derives from, when it models another's Emulsion.
    var derivedFrom: Profile? {
        guard let parent = profile.metadata.derivedFrom else { return nil }
        return catalogue.first { $0.id == parent }
    }

    /// Whether the Stock loses speed at long exposures at all. A Curve Set that
    /// records no failure has nothing for the exposure-time control to change, so
    /// the control is not offered rather than offered and inert.
    var hasReciprocity: Bool { !profile.metadata.reciprocity.isSilent }

    /// Below this the Stock obeys reciprocity exactly, in seconds.
    var reciprocityThresholdSeconds: Double { profile.metadata.reciprocity.thresholdSeconds }

    /// What reciprocity failure costs at the current exposure time, in stops per
    /// channel, positive for a loss.
    var reciprocityLossStops: [Double] {
        profile.metadata.reciprocity.gain(seconds: settings.exposureSeconds).map { -log2($0) }
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

    /// The Contrast Filters this Stock can be shot through, empty when it has none.
    /// Only a black & white Stock has a Monochrome Collapse for glass to act before,
    /// and only one baked from a measured spectral sensitivity knows what each piece
    /// of glass does to it, so the control appears for those Stocks and no others.
    var contrastFilters: [ContrastFilter] {
        profile.metadata.monochrome?.contrastFilters == nil ? [] : ContrastFilter.allCases
    }

    /// What the fitted glass costs in stops, which the render has already paid.
    var contrastFilterStops: Double? {
        profile.metadata.monochrome?.filterFactorStops(settings.contrastFilter)
    }

    /// The Output Stages this Stock can be read by, empty when there is nothing to
    /// choose. Reversal film is the final image and has none; a negative always has
    /// the scan, and has the Print as well when its Profile carries the cubes for
    /// one. A choice of one is not a choice, so the control does not appear for it.
    var outputStages: [OutputStage] {
        guard profile.metadata.colour.outputStage == .scan, profile.metadata.colour.printVariants != nil else { return [] }
        return [.scan, .print]
    }

    /// The Output Stage on screen. Nil in the settings follows the Profile, which for
    /// a negative is the scan, so the control reads as scan until it is moved.
    var outputStage: OutputStage {
        get { settings.outputStage ?? profile.metadata.colour.outputStage }
        set { settings.outputStage = newValue }
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
            let before = try await renderer.render(image: .linear(decoded), profile: .identity, settings: RenderSettings())
            let small = try await renderer.decode(data, maximumDimension: 192)
            try Task.checkCancellation()
            imageGeneration = UUID()
            pixels = nil
            beforePixels = before
            thumbnails = [:]
            presetThumbnails = [:]
            thumbnailInput = small
            preview = decoded
            original = data
            originalDate = ExportDate.originalDate(in: data)
            if exportTask == nil { export = nil }
            scheduleRender()
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }

    private func stockChanged() {
        settings.developmentOffset = Self.developmentOffset(settings.developmentOffset, for: profile)
        settings.contrastFilter = Self.contrastFilter(settings.contrastFilter, for: profile)
        settings.outputStage = Self.outputStage(settings.outputStage, for: profile)
        scheduleRender()
    }

    // MARK: - Preset thumbnails

    /// One Preset as the renderer needs it: something to key the result by, the Stock
    /// it names, and the settings it decoded to. The sheet decodes, because it needs
    /// those settings for the summary line whether a render ever arrives or not.
    struct PresetRender: Identifiable, Sendable, Hashable {
        let id: PersistentIdentifier
        let stockID: String
        let settings: RenderSettings
    }

    private(set) var presetThumbnails: [PersistentIdentifier: RenderedPixels] = [:]
    private var presetThumbnailTask: Task<Void, Never>?

    /// A frame rendered through each Preset, keyed by the Preset rather than by the
    /// Stock. Debounced and cancelling in flight like `scheduleThumbnails()`, and
    /// otherwise its opposite: **each Preset renders at its own decoded settings**,
    /// not at the settings on screen, because a Preset row is a record of a saved look
    /// rather than a preview of the current one. Get that backwards and every row
    /// looks the same.
    ///
    /// The input is the current photo when one is loaded and the Contact Sheet
    /// Reference when none is. That reference is deterministic, is what the contact
    /// sheet itself renders, and carries saturated patches, shadows and lights above
    /// SDR white — so a Preset's look reads as a look rather than as a grey square.
    func schedulePresetThumbnails(_ presets: [PresetRender]) {
        presetThumbnailTask?.cancel()
        // A deleted Preset's render is a picture of nothing anyone can ask for again.
        let live = Set(presets.map(\.id))
        presetThumbnails = presetThumbnails.filter { live.contains($0.key) }
        guard !presets.isEmpty else { return }
        let profiles = catalogueWithIdentity
        presetThumbnailTask = scheduleThumbnails(presets) { preset in
            guard let profile = profiles.first(where: { $0.id == preset.stockID }) else { return nil }
            return (preset.id, profile, preset.settings)
        } store: { [weak self] id, pixels in
            self?.presetThumbnails[id] = pixels
        }
    }

    // MARK: - Export

    /// Where a full-resolution Export has got to. One at a time: the Export path sizes
    /// its Tiles to a memory budget, and two running at once would blow it.
    enum Export {
        case running(ExportProgress)
        case saving
        case finished(ExportRecord)
        case failed(String)
    }

    /// What an Export produced. Reporting only — nothing here is read back into a
    /// render — so the finished sheet can show the file as a record rather than as a
    /// bare share button.
    struct ExportRecord: Sendable, Equatable {
        let url: URL
        /// Nil for the LUT, which is a lattice written as text rather than a raster.
        var pixelWidth: Int?
        var pixelHeight: Int?
        /// The delivery encoding the file is tagged with, and nil for the same reason.
        var output: RenderSettings.Output?
        var byteCount: Int
        /// One for the LUT, which is rendered whole. An image is rendered a Tile at
        /// a time and reports its own count as it goes.
        var tileCount: Int
        var elapsedSeconds: Double
        var savedDate: Date? = nil

        var megapixels: Double? {
            guard let pixelWidth, let pixelHeight else { return nil }
            return Double(pixelWidth * pixelHeight) / 1e6
        }
    }

    private(set) var export: Export?
    var canExport: Bool { original != nil && exportTask == nil }
    var isExporting: Bool {
        switch export { case .running?, .saving?: true; default: false }
    }
    var exportDate: ExportDate = .today
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

    /// Renders the photo at full resolution and saves it to Photos and a shareable file. The
    /// renderer reports per Tile, which is also where it can be cancelled.
    func exportImage() {
        guard let original, let renderer, exportTask == nil else { return }
        let (profile, settings, format) = (profile, exportSettings, exportFormat)
        let creationDate = exportDate.resolve(originalDate: originalDate)
        export = .running(ExportProgress(completedTiles: 0, tileCount: 0))
        // The Tile count belongs to the plan the renderer made, and the only place it
        // is published is the progress report — which arrives on the renderer's own
        // executor and hops to the main actor to be shown. The record needs it at the
        // moment the file is written, before that hop is guaranteed to have landed,
        // so it is also kept here where both sides can reach it.
        let tileCount = OSAllocatedUnfairLock(initialState: 0)
        // The renderer reports from its own executor, so each Tile hops back here.
        let report: @Sendable (ExportProgress) -> Void = { [weak self] progress in
            tileCount.withLock { $0 = max($0, progress.tileCount) }
            Task { @MainActor in
                guard let self, case .running = self.export else { return }
                self.export = .running(progress)
            }
        }
        let started = ContinuousClock.now
        exportTask = Task { [weak self] in
            defer { self?.exportTask = nil }
            do {
                let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                try Task.checkCancellation()
                guard authorization == .authorized || authorization == .limited else {
                    throw FilmError.invalid("Photo not saved. Allow adding photos in Settings to save exports to Photos.")
                }
                let data = try await renderer.export(image: .encoded(original), profile: profile, settings: settings,
                                                     format: format, options: ExportOptions(creationDate: creationDate), progress: report)
                try Task.checkCancellation()
                let url = try Self.write(data, named: "\(profile.id).\(format.fileExtension)")
                self?.export = .saving
                do {
                    // Photos invokes this block on its own queue. Prevent it from
                    // inheriting MainActor and trapping Swift's executor check.
                    try await PHPhotoLibrary.shared().performChanges { @Sendable in
                        let request = PHAssetCreationRequest.forAsset()
                        request.creationDate = creationDate
                        request.addResource(with: .photo, fileURL: url, options: nil)
                    }
                } catch {
                    try? FileManager.default.removeItem(at: url)
                    throw FilmError.invalid("Photo could not be saved to Photos: \(error.localizedDescription)")
                }
                let size = Self.pixelSize(of: data)
                self?.export = .finished(ExportRecord(url: url, pixelWidth: size?.width, pixelHeight: size?.height,
                                                      output: settings.output, byteCount: data.count,
                                                      tileCount: tileCount.withLock { $0 },
                                                      elapsedSeconds: Self.seconds(since: started), savedDate: creationDate))
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
        let started = ContinuousClock.now
        exportTask = Task { [weak self] in
            defer { self?.exportTask = nil }
            do {
                let text = try await renderer.exportedLUT(profile: profile, settings: settings)
                let data = Data(text.utf8)
                let url = try Self.write(data, named: "\(profile.id).cube")
                // No pixel dimensions and no gamut: a LUT is a mapping, not a frame.
                self?.export = .finished(ExportRecord(url: url, byteCount: data.count, tileCount: 1,
                                                      elapsedSeconds: Self.seconds(since: started)))
            } catch {
                self?.export = .failed(error.localizedDescription)
            }
        }
    }

    func cancelExport() {
        guard case .running = export else { return }
        exportTask?.cancel()
        export = nil
    }

    func dismissExport() {
        if isExporting { return }
        export = nil
    }

    /// The Preview's settings with the chosen delivery encoding. Everything else about
    /// the render is what is on screen, which is the point of sharing the shaders.
    private var exportSettings: RenderSettings {
        var settings = settings
        settings.output = exportOutput
        return settings
    }

    /// The written file's own dimensions. The Export renders the decoded original at
    /// full size, which the model never holds, so the count is read back from the
    /// file's header — ImageIO parses that without decoding a pixel.
    private static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }

    private static func seconds(since started: ContinuousClock.Instant) -> Double {
        let elapsed = (ContinuousClock.now - started).components
        return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    }

    private static func write(_ data: Data, named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Why a Preset cannot be applied. `applyPreset` throws exactly these words, so a
    /// Preset row can show them beside its summary without trying and failing first.
    nonisolated static let stockUnavailable = "This Preset's Stock is no longer available"

    func applyPreset(stockID: String, settings: RenderSettings) throws {
        guard catalogueWithIdentity.contains(where: { $0.id == stockID }) else {
            throw FilmError.invalid(Self.stockUnavailable)
        }
        try settings.validate()
        selectedStock = stockID
        self.settings = settings
        // A Preset is a different picture's Adjustments, so nothing held back from
        // this one is still waiting to be switched on.
        stashedAdjustments.removeAll()
        stockChanged()
    }

    /// Glass does not carry across a change of Stock. A colour Stock has no
    /// Monochrome Collapse for a Contrast Filter to act before and refuses the render
    /// outright rather than ignoring it, so this is what keeps a filtered look from
    /// breaking the moment the picker moves — including in the thumbnail strip, which
    /// renders the whole Catalogue at the settings on screen.
    private static func contrastFilter(_ filter: ContrastFilter, for profile: Profile) -> ContrastFilter {
        profile.metadata.monochrome?.weight(for: filter) == nil ? .none : filter
    }

    /// Nor does a Print carry across a change of Stock. A Stock with no Print refuses
    /// the render rather than falling back to its scan, so this is what keeps the
    /// choice from breaking the moment the picker moves — including in the thumbnail
    /// strip, which renders the whole Catalogue at the settings on screen.
    private static func outputStage(_ stage: OutputStage?, for profile: Profile) -> OutputStage? {
        stage == .print && profile.metadata.colour.printVariants == nil ? nil : stage
    }

    private static func developmentOffset(_ offset: Double, for profile: Profile) -> Double {
        let stops = profile.metadata.colour.lutVariants.map(\.pushStops)
        guard let low = stops.min(), let high = stops.max(), low < high else { return 0 }
        return min(max(offset, low), high)
    }

    private func scheduleThumbnails() {
        thumbnailTask?.cancel()
        guard thumbnailInput != nil else { return }
        let settings = settings
        thumbnailTask = scheduleThumbnails(catalogueWithIdentity) { profile in
            (profile.id, profile, settings)
        } store: { [weak self] id, pixels in
            self?.thumbnails[id] = pixels
        }
    }

    /// The render loop both thumbnail schedulers run: debounce, render each item in
    /// order at whatever settings it asks for, and publish as each one lands. The two
    /// differ only in what they are keyed by and where their settings come from — the
    /// Stock strip renders every Profile at the settings on screen, a Preset row
    /// renders one Profile at its own — so the loop itself is written once.
    ///
    /// `plan` names the key, the Profile and the settings for an item, or nil when
    /// there is nothing to render for it. Its settings are clamped across the Stock
    /// the same way `stockChanged()` clamps them, because a Contrast Filter or a Print
    /// does not survive a change of Stock and a Profile refuses the render outright
    /// rather than ignoring the setting.
    private func scheduleThumbnails<Item, Key>(
        _ items: [Item],
        plan: @escaping (Item) -> (key: Key, profile: Profile, settings: RenderSettings)?,
        store: @escaping @MainActor (Key, RenderedPixels) -> Void
    ) -> Task<Void, Never> {
        let input = thumbnailInput
        return Task {
            do {
                try await Task.sleep(for: .milliseconds(200))
                let source = try input ?? ContactSheetReference.image()
                let renderer = try Renderer()
                for item in items {
                    try Task.checkCancellation()
                    guard let (key, profile, settings) = plan(item) else { continue }
                    var adjusted = settings
                    adjusted.developmentOffset = Self.developmentOffset(settings.developmentOffset, for: profile)
                    adjusted.contrastFilter = Self.contrastFilter(settings.contrastFilter, for: profile)
                    adjusted.outputStage = Self.outputStage(settings.outputStage, for: profile)
                    // One item that will not render leaves its own cell developing; it
                    // does not stop the items after it from arriving.
                    guard let result = try? await renderer.render(image: .linear(source), profile: profile,
                                                                  settings: adjusted) else { continue }
                    try Task.checkCancellation()
                    store(key, result)
                }
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }

    func scheduleRender() {
        scheduleThumbnails()
        needsRender = true
        guard renderLoop == nil, preview != nil, renderer != nil else { return }
        renderLoop = Task { [weak self] in
            defer { self?.renderLoop = nil }
            while let self, needsRender {
                needsRender = false
                guard let preview, let renderer else { return }
                let generation = imageGeneration
                let started = ContinuousClock.now
                do {
                    let result = try await renderer.render(image: .linear(preview), profile: profile, settings: settings)
                    guard generation == imageGeneration else { continue }
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
