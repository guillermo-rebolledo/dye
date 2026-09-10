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
        let source = try texture(for: image)
        let writer = try ImageWriter(format: format, output: settings.output,
                                     width: source.width, height: source.height)
        try await renderTiles(source, profile: profile, settings: settings, options: options, progress: progress) {
            writer.write($1, x: $0.x, y: $0.y, width: $0.width, height: $0.height)
        }
        return try writer.encode(quality: options.quality, creationDate: options.creationDate)
    }

    /// The same tiled render, delivered as pixels rather than as a file. This is how a
    /// Tile Seam or a Grain repeat is asserted: it holds the whole frame in memory, so
    /// it is for tests and diagnostics rather than for a 48MP Export.
    public func exportedPixels(image: RenderImage, profile: Profile, settings: RenderSettings = .init(),
                               options: ExportOptions = .init(),
                               progress: (@Sendable (ExportProgress) -> Void)? = nil) async throws -> RenderedPixels {
        let source = try texture(for: image)
        let width = source.width, height = source.height
        var rgba = [Float16](repeating: 0, count: width * height * 4)
        try await renderTiles(source, profile: profile, settings: settings, options: options, progress: progress) { tile, pixels in
            for row in 0..<tile.height {
                let destination = ((tile.y + row) * width + tile.x) * 4
                for index in 0..<(tile.width * 4) { rgba[destination + index] = pixels[row * tile.width * 4 + index] }
            }
        }
        return RenderedPixels(width: width, height: height, rgba: rgba, output: settings.output)
    }

    /// How an Export is divided for this frame, Profile and settings, without running
    /// it. The app shows the Tile count; the tests assert the Apron against the reach
    /// of the widest Pass.
    public func tilePlan(image: RenderImage, profile: Profile, settings: RenderSettings = .init(),
                         options: ExportOptions = .init()) throws -> TilePlan {
        let source = try texture(for: image)
        return try tilePlan(source, profile: profile, settings: settings, options: options)
    }

    private func tilePlan(_ source: any MTLTexture, profile: Profile, settings: RenderSettings,
                          options: ExportOptions) throws -> TilePlan {
        try settings.validate()
        let tiling = try tiling(profile: profile, settings: settings, source: source,
                                scatterFraction: options.apronFraction)
        return try TilePlan(frameWidth: source.width, frameHeight: source.height,
                            apron: tiling.apron, alignment: tiling.alignment,
                            budgetBytes: options.textureBudgetBytes, minimumCore: options.minimumTileEdge)
    }

    /// The tiled loop both public entry points share. `sink` receives each Tile's core,
    /// with the Apron already discarded.
    private func renderTiles(_ source: any MTLTexture, profile: Profile, settings: RenderSettings,
                             options: ExportOptions, progress: (@Sendable (ExportProgress) -> Void)?,
                             sink: (TilePlan.Tile, UnsafeBufferPointer<Float16>) throws -> Void) async throws {
        let plan = try tilePlan(source, profile: profile, settings: settings, options: options)
        let thermalState = options.resolvedThermalState
        let grainModel = Self.grainModel(profile, path: .export, thermalState: thermalState)
        let input = try decoder.makeTexture(width: plan.paddedWidth, height: plan.paddedHeight)
        let scratch = try decoder.makeTexture(width: plan.paddedWidth, height: plan.paddedHeight)
        var core = [Float16](repeating: 0, count: plan.coreWidth * plan.coreHeight * 4)
        progress?(ExportProgress(completedTiles: 0, tileCount: plan.count))
        for index in 0..<plan.count {
            try Task.checkCancellation()
            let tile = plan.tile(index)
            try copy(source, into: input, from: tile, plan: plan)
            let frame = Frame(width: plan.frameWidth, height: plan.frameHeight,
                              originX: tile.originX, originY: tile.originY)
            let result = try renderTile(input, into: scratch, frame: frame, profile: profile,
                                        settings: settings, queue: exportQueue, grainModel: grainModel)
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
                      from region: TilePlan.Tile, plan: TilePlan) throws {
        guard let command = exportQueue.makeCommandBuffer(), let blit = command.makeBlitCommandEncoder() else {
            throw FilmError.invalid("Cannot read the tile from the frame")
        }
        blit.copy(from: source, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: region.originX, y: region.originY, z: 0),
                  sourceSize: MTLSize(width: plan.paddedWidth, height: plan.paddedHeight, depth: 1),
                  to: tile, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw error }
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
