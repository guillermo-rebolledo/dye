import Foundation
import Metal

extension Renderer {
    /// The Export Render Path: the frame at full resolution, a Tile at a time, encoded
    /// to a file. Identical shaders to the Preview, and identical output to an untiled
    /// render of the same frame — the Apron and the frame-global Grain coordinate are
    /// what buy that, and `exportedPixels` is where the tests assert it.
    ///
    /// Cancellable and progress-reporting per Tile, and suspending between Tiles, so a
    /// long Export neither blocks the caller's actor nor starves the Preview: the work
    /// goes to a command queue of its own.
    public func export(image: RenderImage, profile: Profile, settings: RenderSettings = .init(),
                       format: ExportFormat = .heif, options: ExportOptions = .init(),
                       progress: (@Sendable (ExportProgress) -> Void)? = nil) async throws -> Data {
        // The decoded frame is the Export's largest single allocation — 372MB at 48MP —
        // and the last Tile is the last thing that needs it. Encoding inside its scope
        // would hold it alongside the assembled output frame for no reason, so the
        // scope ends before the encoder starts.
        let writer: ImageWriter
        do {
            let source = try await texture(for: image)
            writer = try ImageWriter(format: format, output: settings.output,
                                     width: source.width, height: source.height)
            try await renderTiles(source, profile: profile, settings: settings, options: options, progress: progress) {
                writer.write($1, x: $0.x, y: $0.y, width: $0.width, height: $0.height)
            }
        }
        return try writer.encode(quality: options.quality, creationDate: options.creationDate)
    }

    /// The Export as a file the engine owns, which is how the app gets one.
    ///
    /// `export` returns bytes and is the diagnostic form; this is the shipping one,
    /// because the bytes have to land on disk for Photos and for the share sheet, and
    /// a full-resolution copy of a photograph is not something to leave lying around
    /// once the user has finished with it. `ExportedFile` carries that lifetime.
    public func exportFile(image: RenderImage, profile: Profile, settings: RenderSettings = .init(),
                           format: ExportFormat = .heif, options: ExportOptions = .init(),
                           progress: (@Sendable (ExportProgress) -> Void)? = nil,
                           in directory: URL = ExportedFile.temporaryRoot) async throws -> ExportedFile {
        let data = try await export(image: image, profile: profile, settings: settings,
                                    format: format, options: options, progress: progress)
        return try Self.store(data, stem: profile.metadata.filenameStem, extension: format.fileExtension, in: directory)
    }

    /// The Exported LUT, owned the same way. It is a lattice written as text rather
    /// than a raster, but it is still a file the app would otherwise never delete.
    public func exportedLUTFile(profile: Profile, settings: RenderSettings = .init(), size: Int = 33,
                                in directory: URL = ExportedFile.temporaryRoot) async throws -> ExportedFile {
        let text = try await exportedLUT(profile: profile, settings: settings, size: size)
        return try Self.store(Data(text.utf8), stem: profile.metadata.filenameStem, extension: "cube", in: directory)
    }

    /// Cancellation that lands after the bytes are on disk still has to clean up, so
    /// the handle is only ever returned to a caller that can still use it.
    private static func store(_ data: Data, stem: String, extension fileExtension: String,
                              in directory: URL) throws -> ExportedFile {
        try Task.checkCancellation()
        let file = try ExportedFile.write(data, named: ExportedFile.fileName(stem, extension: fileExtension), in: directory)
        if Task.isCancelled {
            file.discard()
            throw CancellationError()
        }
        return file
    }

    /// The same tiled render, delivered as pixels rather than as a file. This is how a
    /// Tile Seam or a Grain repeat is asserted: it holds the whole frame in memory, so
    /// it is for tests and diagnostics rather than for a 48MP Export.
    public func exportedPixels(image: RenderImage, profile: Profile, settings: RenderSettings = .init(),
                               options: ExportOptions = .init(),
                               progress: (@Sendable (ExportProgress) -> Void)? = nil) async throws -> RenderedPixels {
        let source = try await texture(for: image)
        let width = source.width, height = source.height
        var rgba = [Float16](repeating: 0, count: width * height * 4)
        try await renderTiles(source, profile: profile, settings: settings, options: options, progress: progress) { tile, pixels in
            // A row at a time rather than a component at a time: the Tile's rows are
            // contiguous and so are the frame's, and only where they meet differs.
            rgba.withUnsafeMutableBufferPointer { frame in
                for row in 0..<tile.height {
                    let destination = ((tile.y + row) * width + tile.x) * 4
                    let source = row * tile.width * 4
                    UnsafeMutableBufferPointer(rebasing: frame[destination..<(destination + tile.width * 4)])
                        .update(from: UnsafeBufferPointer(rebasing: pixels[source..<(source + tile.width * 4)]))
                }
            }
        }
        return RenderedPixels(width: width, height: height, rgba: rgba, output: settings.output)
    }

    /// How an Export is divided for this frame, Profile and settings, without running
    /// it. The app shows the Tile count; the tests assert the Apron against the reach
    /// of the widest Pass.
    public func tilePlan(image: RenderImage, profile: Profile, settings: RenderSettings = .init(),
                         options: ExportOptions = .init()) async throws -> TilePlan {
        let source = try await texture(for: image)
        return try tilePlan(frameWidth: source.width, frameHeight: source.height, profile: profile,
                            settings: settings, options: options)
    }

    /// How an Export would divide a frame of this size, without decoding one. The
    /// Tile plan depends on the frame's dimensions and on the Profile's reach, never
    /// on its pixels, so the regression table can span the sizes a phone actually
    /// hands the Export without allocating a 372MB texture for each of them.
    public func tilePlan(frameWidth: Int, frameHeight: Int, profile: Profile,
                         settings: RenderSettings = .init(),
                         options: ExportOptions = .init()) throws -> TilePlan {
        try resolvePlans(frameWidth: frameWidth, frameHeight: frameHeight, profile: profile,
                         settings: settings, options: options, grainModel: .procedural).tiles
    }

    /// The Tile plan and the render Plan every Tile of it shares, resolved together.
    ///
    /// Both come from the same reading of the Profile against the frame, so building
    /// them separately would resolve the Stock, fit the MTF and build the Grain table
    /// twice before the first Tile is rendered — and again for every Tile after it.
    /// A Plan is consulted about the Tile for exactly one thing, how deep a Scattering
    /// Pyramid fits in it, so a padded Tile that can carry the depth the frame
    /// resolved to renders against the frame's own Plan unchanged.
    private func resolvePlans(frameWidth: Int, frameHeight: Int, profile: Profile, settings: RenderSettings,
                              options: ExportOptions,
                              grainModel: GrainModel) throws -> (tiles: TilePlan, render: Plan) {
        try settings.validate()
        guard frameWidth > 0, frameHeight > 0 else { throw FilmError.invalid("Frame must have a positive size") }
        let tiling = try tiling(profile: profile, settings: settings, frameWidth: frameWidth,
                                frameHeight: frameHeight, scatterFraction: options.apronFraction,
                                grainModel: grainModel)
        let tiles = try TilePlan(frameWidth: frameWidth, frameHeight: frameHeight,
                                 apron: tiling.apron, alignment: tiling.alignment,
                                 budgetBytes: options.resolvedTextureBudgetBytes, minimumCore: options.minimumTileEdge)
        let available = Scatter.depthAvailable(tileWidth: tiles.paddedWidth, tileHeight: tiles.paddedHeight)
        guard available < tiling.plan.scatterDepth else { return (tiles, tiling.plan) }
        // A Tile too small to carry the frame's pyramid resolves a shallower one. Still
        // once for the Export: every Tile is rendered at the same padded size.
        let render = try plan(profile: profile, settings: settings,
                              frame: Frame(width: frameWidth, height: frameHeight),
                              tileWidth: tiles.paddedWidth, tileHeight: tiles.paddedHeight,
                              spatial: true, grainModel: grainModel)
        return (tiles, render)
    }

    /// The tiled loop both public entry points share. `sink` receives each Tile's core,
    /// with the Apron already discarded.
    private func renderTiles(_ source: any MTLTexture, profile: Profile, settings: RenderSettings,
                             options: ExportOptions, progress: (@Sendable (ExportProgress) -> Void)?,
                             sink: (TilePlan.Tile, UnsafeBufferPointer<Float16>) throws -> Void) async throws {
        let thermalState = options.resolvedThermalState
        let grainModel = Self.grainModel(profile, path: .export, thermalState: thermalState)
        let plans = try resolvePlans(frameWidth: source.width, frameHeight: source.height, profile: profile,
                                     settings: settings, options: options, grainModel: grainModel)
        let plan = plans.tiles
        let input = try decoder.makeTexture(width: plan.paddedWidth, height: plan.paddedHeight)
        let scratch = try decoder.makeTexture(width: plan.paddedWidth, height: plan.paddedHeight)
        var core = [Float16](repeating: 0, count: plan.coreWidth * plan.coreHeight * 4)
        progress?(ExportProgress(completedTiles: 0, tileCount: plan.count))
        for index in 0..<plan.count {
            try Task.checkCancellation()
            let tile = plan.tile(index)
            try await copy(source, into: input, from: tile, plan: plan)
            let frame = Frame(width: plan.frameWidth, height: plan.frameHeight,
                              originX: tile.originX, originY: tile.originY)
            let result = try await renderTile(input, into: scratch, plan: plans.render, frame: frame,
                                              profile: profile, settings: settings, queue: exportQueue)
            core.withUnsafeMutableBytes {
                result.getBytes($0.baseAddress!, bytesPerRow: tile.width * 8,
                                from: MTLRegionMake2D(tile.insetX, tile.insetY, tile.width, tile.height), mipmapLevel: 0)
            }
            try core.withUnsafeBufferPointer { try sink(tile, UnsafeBufferPointer(rebasing: $0[0..<(tile.width * tile.height * 4)])) }
            progress?(ExportProgress(completedTiles: index + 1, tileCount: plan.count))
            // Between Tiles rather than during one: a command buffer is already
            // committed and waited on, so this is where the actor can service the
            // Preview, where a cancellation lands, and where a hot device gets a gap
            // long enough to be worth having.
            if thermalState.isThrottling { try await Task.sleep(for: .milliseconds(50)) } else { await Task.yield() }
        }
    }

    /// Fills the Tile texture with its region of the frame, Apron included. Regions
    /// are always fully inside the frame — `TilePlan` slides the Apron rather than
    /// letting it hang over the edge — so the Apron a border Tile lacks is simply the
    /// clamp the Passes already apply at the frame edge.
    private func copy(_ source: any MTLTexture, into tile: any MTLTexture,
                      from region: TilePlan.Tile, plan: TilePlan) async throws {
        guard let command = exportQueue.makeCommandBuffer(), let blit = command.makeBlitCommandEncoder() else {
            throw FilmError.invalid("Cannot read the tile from the frame")
        }
        blit.copy(from: source, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: region.originX, y: region.originY, z: 0),
                  sourceSize: MTLSize(width: plan.paddedWidth, height: plan.paddedHeight, depth: 1),
                  to: tile, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        try await withCheckedThrowingContinuation(Self.completion(command))
    }

    /// Preview and Export keep the same physical Grain Model at every thermal
    /// state. Scheduling or resolution can change, but the model does not.
    /// Stochastic grain is not implemented and retains its procedural fallback.
    public static func grainModel(_ profile: Profile, path: RenderPath,
                                  thermalState: ProcessInfo.ThermalState) -> GrainModel {
        // Temperature and Render Path may affect scheduling/resolution, not the
        // physical grain model. Stochastic remains an explicitly unsupported
        // authoring choice and retains the existing procedural fallback.
        profile.metadata.grain.model == .stochastic ? .procedural : profile.metadata.grain.model
    }
}
