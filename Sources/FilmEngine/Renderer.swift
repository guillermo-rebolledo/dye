import Foundation
import Metal
import simd

/// Owns its command queue and resources; callers can render off the main actor.
public actor Renderer {
    private let device: any MTLDevice
    private let queue: any MTLCommandQueue
    /// Export submits from its own queue so a long tiled render does not sit in front
    /// of the Preview's next frame in the same queue's ordering.
    let exportQueue: any MTLCommandQueue
    private let pipelines: [String: any MTLComputePipelineState]
    let decoder: ImageDecoder
    private let textureCacheCapacity: Int
    private var responseCache: [ResponseEntry] = []
    /// One per Scattering Pass: Bloom and Halation ask for different radii, so they
    /// resolve to pyramids of different depths and cannot share one allocation.
    private var pyramids: [Scattering: Pyramid] = [:]
    private var mtfTextures: [any MTLTexture]?

    private struct ResponseEntry {
        let id: UUID
        let name: String
        let texture: any MTLTexture
        /// Density Space value of Working Space mid-grey, the scan's auto-balance reference.
        let grayDensity: SIMD3<Double>
        /// Density Space value of zero exposure, the scan's black point.
        let baseDensity: SIMD3<Double>
    }

    public init(textureCacheCapacity: Int = 4) throws {
        guard (2...32).contains(textureCacheCapacity) else { throw FilmError.invalid("Texture cache capacity must be 2...32") }
        self.textureCacheCapacity = textureCacheCapacity
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let exportQueue = device.makeCommandQueue() else {
            throw FilmError.invalid("Metal is unavailable")
        }
        self.device = device
        self.queue = queue
        self.exportQueue = exportQueue
        exportQueue.label = "FilmEngine.export"
        decoder = try ImageDecoder(device: device)
        let url = Bundle.module.url(forResource: "Pipeline", withExtension: "metal", subdirectory: "Metal")!
        let options = MTLCompileOptions()
        if #available(macOS 15, iOS 18, *) { options.mathMode = .safe }
        else { options.fastMathEnabled = false }
        let library = try device.makeLibrary(source: String(contentsOf: url, encoding: .utf8), options: options)
        var pipelines: [String: any MTLComputePipelineState] = [:]
        for name in ["passthrough", "whiteBalance", "exposure", "reciprocity", "filmResponse", "monochromeResponse", "scanOutput", "outputTransform",
                     "scatterThreshold", "scatterDownsample", "scatterBlurHorizontal", "scatterBlurVertical",
                     "scatterScale", "scatterUpsample", "scatterComposite",
                     "mtfBlur", "mtfCombine", "grain", "grainDyeCloud", "adjust", "geometry"] {
            guard let function = library.makeFunction(name: name) else { throw FilmError.invalid("Missing shader \(name)") }
            pipelines[name] = try device.makeComputePipelineState(function: function)
        }
        self.pipelines = pipelines
    }

    /// Colour-managed decode into the Working Space, optionally downsampled for the
    /// Preview Render Path so slider changes re-render a screen-sized image.
    public func decode(_ data: Data, maximumDimension: Int? = nil) throws -> LinearImage {
        let texture = try decoder.decode(data, maximumDimension: maximumDimension)
        return try readback(texture)
    }

    /// The sole renderer test seam. Encoded input is colour-managed before Metal;
    /// linear input already belongs to the Working Space. All thirteen passes run.
    ///
    /// This is the Preview Render Path: one Tile that is the whole frame. `export`
    /// runs the same graph over many Tiles of one frame.
    public func render(image: RenderImage, profile: Profile, settings: RenderSettings = .init()) throws -> RenderedPixels {
        try settings.validate()
        let input = try texture(for: image)
        let scratch = try decoder.makeTexture(width: input.width, height: input.height)
        let result = try renderTile(input, into: scratch, frame: Frame(width: input.width, height: input.height),
                                    profile: profile, settings: settings, queue: queue)
        let pixels = try readback(result)
        return RenderedPixels(width: pixels.width, height: pixels.height, rgba: pixels.rgba, output: settings.output)
    }

    func texture(for image: RenderImage) throws -> any MTLTexture {
        switch image {
        case .encoded(let data): return try decoder.decode(data)
        case .linear(let image):
            let texture = try decoder.makeTexture(width: image.width, height: image.height)
            image.rgba.withUnsafeBytes {
                texture.replace(region: MTLRegionMake2D(0, 0, image.width, image.height), mipmapLevel: 0,
                                withBytes: $0.baseAddress!, bytesPerRow: image.width * 8)
            }
            return texture
        }
    }

    /// Where a Tile sits in the frame it belongs to. A Preview is one Tile that *is*
    /// the frame; an Export is many. Everything measured in Film-Plane Microns
    /// converts through the frame rather than through the Tile, and Grain and the
    /// Geometry Pass are given the origin, which together are what make a Tile a
    /// window onto the untiled render rather than a small render of its own.
    struct Frame: Sendable, Equatable {
        let width: Int, height: Int
        var originX = 0, originY = 0
        var packed: SIMD4<Float> { SIMD4(Float(originX), Float(originY), Float(width), Float(height)) }
    }

    /// Runs the pass graph over one Tile and returns whichever of the two ping-pong
    /// textures holds the result. `spatial` is what an Exported LUT turns off: it
    /// carries the colour half of the look and nothing that reads a neighbour.
    func renderTile(_ input: any MTLTexture, into scratch: any MTLTexture, frame: Frame,
                    profile: Profile, settings: RenderSettings, queue: any MTLCommandQueue,
                    spatial: Bool = true, grainModel: GrainModel = .procedural) throws -> any MTLTexture {
        let plan = try plan(profile: profile, settings: settings, frame: frame, tile: input,
                            spatial: spatial, grainModel: grainModel)
        guard let command = queue.makeCommandBuffer() else { throw FilmError.invalid("Cannot create render command") }
        var frameUniform = frame.packed
        var source = input
        var destination = scratch
        for pass in Pass.allCases {
            // Four passes need more than one dispatch, or resources of their own, so
            // they encode themselves rather than going through the loop below. A Pass
            // the Plan resolved to nil does not run at all, and releases whatever it
            // was holding: neither a Stock nor an intensity that will not use those
            // textures should keep them alive.
            if let scattering = Scattering(pass) {
                guard let scatter = scattering == .bloom ? plan.bloom : plan.halation else {
                    pyramids[scattering] = nil
                    continue
                }
                try encodeScatter(scatter, scattering, command: command, source: source, destination: destination)
                swap(&source, &destination)
                continue
            }
            if pass == .mtf {
                guard let mtf = plan.mtf else { mtfTextures = nil; continue }
                try encodeMTF(mtf, command: command, source: source, destination: destination)
                swap(&source, &destination)
                continue
            }
            if pass == .grain {
                guard let grain = plan.grain else { continue }
                try encodeGrain(grain, frame: &frameUniform, command: command, source: source, destination: destination)
                swap(&source, &destination)
                continue
            }
            if pass == .geometry {
                guard let geometry = plan.geometry else { continue }
                try encodeGeometry(geometry, frame: &frameUniform, command: command, source: source, destination: destination)
                swap(&source, &destination)
                continue
            }
            let name = pipelineName(for: pass, plan: plan, profile: profile)
            guard let encoder = command.makeComputeCommandEncoder(), let pipeline = pipelines[name] else {
                throw FilmError.invalid("Cannot encode \(pass)")
            }
            encoder.label = pass.rawValue
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(source, index: 0)
            encoder.setTexture(destination, index: 1)
            encoder.setTexture(plan.lower.texture, index: 2)
            encoder.setTexture((plan.upper ?? plan.lower).texture, index: 3)
            var output = settings.output.rawValue
            encoder.setBytes(&output, length: MemoryLayout<UInt32>.size, index: 0)
            var weights = plan.spectralWeight
            encoder.setBytes(&weights, length: MemoryLayout<SIMD4<Float>>.size, index: 1)
            var matrix = plan.whiteBalance ?? matrix_identity_float3x3
            encoder.setBytes(&matrix, length: MemoryLayout<simd_float3x3>.size, index: 2)
            var gain = plan.gain
            encoder.setBytes(&gain, length: MemoryLayout<Float>.size, index: 3)
            var shaper = plan.shaper
            encoder.setBytes(&shaper, length: MemoryLayout<SIMD4<Float>>.size, index: 4)
            var blend = SIMD4<Float>(plan.blend, 0, 0, 0)
            encoder.setBytes(&blend, length: MemoryLayout<SIMD4<Float>>.size, index: 5)
            var gray = plan.grayDensity
            encoder.setBytes(&gray, length: MemoryLayout<SIMD4<Float>>.size, index: 6)
            var base = plan.baseDensity
            encoder.setBytes(&base, length: MemoryLayout<SIMD4<Float>>.size, index: 7)
            var failure = plan.reciprocity ?? SIMD4(repeating: 1)
            encoder.setBytes(&failure, length: MemoryLayout<SIMD4<Float>>.size, index: 13)
            var adjustments = plan.adjustments ?? AdjustmentUniforms(tone: .zero, colour: .zero)
            encoder.setBytes(&adjustments, length: MemoryLayout<AdjustmentUniforms>.stride, index: 15)
            encoder.dispatchThreads(MTLSize(width: input.width, height: input.height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            encoder.endEncoding()
            swap(&source, &destination)
        }
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        return source
    }

    private struct Plan {
        let whiteBalance: simd_float3x3?
        let gain: Float
        /// Per-channel Reciprocity Failure, or nil when the frame was short enough
        /// that the Stock obeys reciprocity and the Pass has nothing to do.
        let reciprocity: SIMD4<Float>?
        /// The Monochrome Collapse's weights, already normalised so the Contrast
        /// Filter costs tonal separation rather than exposure. Zero for a colour Stock.
        let spectralWeight: SIMD4<Float>
        let lower: ResponseEntry
        let upper: ResponseEntry?
        let blend: Float
        let shaper: SIMD4<Float>
        let scan: Bool
        let grayDensity: SIMD4<Float>
        let baseDensity: SIMD4<Float>
        /// The Adjustment Pass's controls, or nil when every one is at zero and the
        /// Pass has nothing to do. Per-pixel, so an Exported LUT carries it.
        let adjustments: AdjustmentUniforms?
        let bloom: Scatter?
        let halation: Scatter?
        let mtf: MTF?
        let grain: Grain?
        let geometry: Geometry?

        // Between them, these are the Apron a Tile of this frame has to carry. The
        // Film Response, the Output Stage and the Output Transform are per-pixel and
        // reach nothing at all.

        /// The Scattering Passes' reach: wide, and the only part of the Apron worth
        /// trading against, because it is also the only part whose furthest pixels
        /// carry almost none of the halo. Widest is the modelled lens's Bloom at 900
        /// µm — further than even Cinestill's Halation, which MEM-252 expected to
        /// dominate, because Bloom did not have a Pass when it was written.
        var scatterReach: Double { max(bloom?.reach ?? 0, halation?.reach ?? 0) }

        /// What the rest of the pipeline reaches, which is small and never traded away.
        var exactReach: Int {
            // The MTF's two Gaussians are truncated kernels of an exact tap count, and
            // both read the Pass's source rather than each other, so the coarse one
            // alone bounds the reach.
            var pixels = Double(mtf.map { max($0.fine.y, $0.coarse.y) } ?? 0)
            // The gate displaces the frame by a fixed amount and reads bilinearly.
            pixels = max(pixels, geometry.map { Double(max(abs($0.weave.x), abs($0.weave.y))) + 1 } ?? 0)
            return Int(pixels.rounded(.up))
        }

        /// What a Tile origin has to be a multiple of for the Scattering Pyramids to
        /// halve the same grid in every Tile.
        var alignment: Int { max(bloom?.alignment ?? 1, halation?.alignment ?? 1) }
    }

    /// The two Passes that blur before the Film Response, in the order the light
    /// meets them: the taking lens first, then the film's own base.
    private enum Scattering: String, Hashable {
        case bloom, halation
        init?(_ pass: Pass) {
            switch pass { case .bloom: self = .bloom; case .halation: self = .halation; default: return nil }
        }
    }

    /// Everything a Scattering Pass needs, resolved against the image it will run on.
    private struct Scatter {
        /// (threshold, knee half-width, strength × intensity, how much of the source
        /// the scattered light replaces rather than adds to).
        let parameters: SIMD4<Float>
        let tint: SIMD4<Float>
        /// Per level, how much of that level each channel takes. Sums to one per channel.
        let levelWeights: [SIMD4<Float>]
        /// The coarsest pyramid level any channel draws from, or nil when only the
        /// unblurred extract does and the Pass reaches no further than its own pixel.
        let topLevel: Int?

        /// How far this Pass draws light from, in pixels.
        ///
        /// Not a multiple of the sigma. Every blur in the pyramid is a *truncated*
        /// kernel — five texels either side at each level — so unlike the Gaussian it
        /// approximates, the chain has finite support, and an Apron that wide makes a
        /// Tile exactly a window onto the untiled render instead of approximately one.
        ///
        /// Per axis and in level-zero pixels: level 0's own blur reaches 5; each level
        /// after it reaches 10.5 of its own texels through the blur and the 2×2 average
        /// that fed it, which is 5.25 · 2^L; and the bilinear step back down the levels
        /// adds one coarse texel each, 2^(L+1) − 2 in total. Summing gives
        /// 12.5 · 2^L − 7.5, which is around three and a half sigmas at the coarse
        /// levels and nearer nine at the fine ones — the reason a sigma multiple sized
        /// for one end of the pyramid under-provisions the other.
        var reach: Double { topLevel.map { 12.5 * Double(1 << $0) - 7.5 } ?? 0 }

        /// The pyramid's 2×2 averaging pairs texels from the texture's own origin, so
        /// a Tile whose origin is not a multiple of this halves a different grid from
        /// its neighbour and their halos disagree by up to half a coarse texel.
        var alignment: Int { topLevel.map { 1 << $0 } ?? 1 }
    }

    /// The Stock's published response curve fitted to two Gaussians for this image.
    private struct MTF {
        /// (direct, fine, coarse, unused) weights summing to one.
        let coefficients: SIMD4<Float>
        /// (sigma, kernel radius) in pixels, for the fine and the coarse Gaussian.
        let fine: SIMD2<Float>
        let coarse: SIMD2<Float>
    }

    /// Laid out to match `AdjustmentUniforms` in the shader: `tone` is (black point,
    /// brightness, shadows, highlights) and `colour` is (contrast, saturation,
    /// vibrance, unused), with Brilliance already folded in by `adjustments(_:)`.
    private struct AdjustmentUniforms {
        var tone: SIMD4<Float>
        var colour: SIMD4<Float>
    }

    /// Laid out to match `GrainUniforms` in the shader; every member is 16-byte aligned.
    private struct GrainUniforms {
        var sigma: SIMD4<Float>
        var cell: SIMD4<Float>
        var mix: SIMD4<Float>
        var base: SIMD4<Float>
        var scale: SIMD4<Float>
        var seed: SIMD4<UInt32>
    }

    /// The Geometry Pass's parameters, all of them already in pixels.
    private struct Geometry {
        let vignette: Float
        /// The gate's displacement, fixed by the Seed rather than animated.
        let weave: SIMD2<Float>
        /// Half the width of the unexposed rebate around the frame.
        let border: Float
        var packed: SIMD4<Float> { SIMD4(vignette, weave.x, weave.y, border) }
    }

    private struct Grain {
        let uniforms: GrainUniforms
        /// The Profile's 32-entry Density Response, passed as its own buffer.
        let response: [Float]
        /// Which tier renders the field. `Renderer.grainModel` has already applied the
        /// Render Path and the device's thermal state by the time this is set.
        let model: GrainModel
    }

    /// Resolves the Profile and the user's settings against the frame. Sizes come
    /// from `frame`, never from `tile`: a Tile is a window onto one frame, so a
    /// Halation radius, a grain cell and a vignette all have to be the frame's.
    /// `tile` is consulted only for how deep a Scattering Pyramid will fit in it.
    private func plan(profile: Profile, settings: RenderSettings, frame: Frame,
                      tile: any MTLTexture, spatial: Bool, grainModel: GrainModel = .procedural) throws -> Plan {
        let metadata = profile.metadata
        let width = frame.width, height = frame.height
        let whiteBalance = WhiteBalance.matrix(sceneKelvin: settings.temperatureKelvin, tint: settings.tint, stockBalanceKelvin: metadata.balance)
        // A Stock with no Output Stage has none whatever the settings ask for: there
        // is nothing after a reversal Stock's film to choose between, and a forced
        // scan would invert an image that is already the Transparency. The override
        // is how a negative is read in Density Space, not a way to add a stage.
        let stage = metadata.colour.outputStage == OutputStage.none
            ? OutputStage.none : (settings.outputStage ?? metadata.colour.outputStage)
        // The Print is a second set of baked Colour Cubes rather than a Pass: what
        // the enlarger and the paper do to a negative is a spectral integral, so it
        // is resolved where the scan's is. A Stock with no Print is told so rather
        // than given the scan's cubes under the print's name.
        guard stage != .print || metadata.colour.printVariants != nil else {
            throw FilmError.invalid("Profile \(metadata.id): no Print Output Stage")
        }
        // Development Offsets are clamped to the baked range for both the Colour Cube
        // choice and the rating that goes with it. Between variants both blend linearly.
        let variants = (stage == .print ? metadata.colour.printVariants! : metadata.colour.lutVariants)
            .sorted { $0.pushStops < $1.pushStops }
        var offset = settings.developmentOffset
        var lowerVariant: FilmProfile.Variant?
        var upperVariant: FilmProfile.Variant?
        var blend: Float = 0
        if let first = variants.first, let last = variants.last {
            offset = min(max(offset, first.pushStops), last.pushStops)
            if let exact = variants.first(where: { $0.pushStops == offset }) {
                lowerVariant = exact
            } else {
                lowerVariant = variants.last { $0.pushStops < offset }
                upperVariant = variants.first { $0.pushStops > offset }
                blend = Float((offset - lowerVariant!.pushStops) / (upperVariant!.pushStops - lowerVariant!.pushStops))
            }
        } else { offset = 0 }
        // Metering is at True Speed, not Box Speed: a Stock that behaves slower than
        // the box says is given the light a meter set to what it actually is would
        // have given it. Cinestill 800T and Velvia 50 are the two the Catalogue
        // records a difference for; for every other Stock this term is zero.
        let rating = log2(metadata.nominalISO / metadata.trueISO)
        let gain = Float(pow(2, settings.exposureStops - offset + rating))
        let failure = metadata.reciprocity.gain(seconds: settings.exposureSeconds)
        let reciprocity = failure.contains { $0 != 1 }
            ? SIMD4(Float(failure[0]), Float(failure[1]), Float(failure[2]), 0) : nil
        // The Contrast Filter selects which Spectral Weight the collapse uses. It is
        // black & white only, and a Profile baked before Contrast Filters existed has
        // none to select — neither is a silent fallback to the unfiltered weight.
        guard settings.contrastFilter == .none || metadata.monochrome != nil else {
            throw FilmError.invalid("Profile \(metadata.id): a Contrast Filter needs a Monochrome Collapse to act on")
        }
        var spectralWeight = SIMD4<Float>(repeating: 0)
        if let monochrome = metadata.monochrome {
            guard let weight = monochrome.weight(for: settings.contrastFilter) else {
                throw FilmError.invalid("Profile \(metadata.id): no Spectral Weight for the \(settings.contrastFilter.rawValue) Contrast Filter")
            }
            spectralWeight = SIMD4(Float(weight[0]), Float(weight[1]), Float(weight[2]), 0)
        }
        let lower = try responseEntry(for: profile, name: metadata.monochrome?.densityCurve ?? lowerVariant?.lut)
        let upper = try upperVariant.map { try responseEntry(for: profile, name: $0.lut) }
        var shaper = SIMD4<Float>(repeating: 0)
        if let s = metadata.colour.inputShaper {
            shaper = SIMD4(1, Float(s.minimumLogExposure), Float(1 / (s.maximumLogExposure - s.minimumLogExposure)), Float(s.middleGrayLogExposure))
        }
        // Spectral cubes already contain the Baker's scan or print; a Density Space
        // cube is scanned here.
        let scan = stage == .scan && metadata.colour.cubeOutput != .displayLinearRec2020
        func blended(_ value: (ResponseEntry) -> SIMD3<Double>) -> SIMD3<Double> {
            value(lower) + (upper.map { (value($0) - value(lower)) * Double(blend) } ?? SIMD3(repeating: 0))
        }
        let gray = blended(\.grayDensity), base = blended(\.baseDensity)
        if scan, (0..<3).contains(where: { gray[$0] - base[$0] < 0.001 }) {
            throw FilmError.invalid("Profile \(metadata.id): mid-grey density is not above base density; the scan cannot auto-balance")
        }
        return Plan(whiteBalance: whiteBalance, gain: gain, reciprocity: reciprocity, spectralWeight: spectralWeight,
                    lower: lower, upper: upper, blend: blend, shaper: shaper, scan: scan,
                    grayDensity: SIMD4(Float(gray.x), Float(gray.y), Float(gray.z), scan ? 1 : 0),
                    baseDensity: SIMD4(Float(base.x), Float(base.y), Float(base.z), 0),
                    adjustments: Self.adjustments(settings.adjustments),
                    bloom: spatial ? bloom(profile: profile, settings: settings, frame: frame, tile: tile) : nil,
                    halation: spatial ? halation(profile: profile, settings: settings, frame: frame, tile: tile) : nil,
                    mtf: spatial ? mtf(profile: profile, width: width, height: height) : nil,
                    grain: spatial ? grain(profile: profile, settings: settings, width: width, height: height,
                                           base: base, gray: gray, model: grainModel) : nil,
                    geometry: spatial ? geometry(profile: profile, settings: settings, width: width, height: height) : nil)
    }

    /// Brilliance is not a curve of its own. It is the three moves a photo editor
    /// makes to bring detail out — open the shadows, pull the highlights back, add
    /// a little contrast in the middle — made together, so it resolves here to those
    /// three controls and the shader never sees it. All three sums are clamped to
    /// ±1, which is the range each term's gain is chosen to stay monotone over: a
    /// sum past it would be a fourth control's worth of curve, not a stronger one.
    private static func adjustments(_ a: Adjustments) -> AdjustmentUniforms? {
        guard !a.isNeutral else { return nil }
        let shadows = min(max(a.shadows + 0.6 * a.brilliance, -1), 1)
        let highlights = min(max(a.highlights - 0.5 * a.brilliance, -1), 1)
        let contrast = min(max(a.contrast + 0.3 * a.brilliance, -1), 1)
        return AdjustmentUniforms(tone: SIMD4(Float(a.blackPoint), Float(a.brightness), Float(shadows), Float(highlights)),
                                  colour: SIMD4(Float(contrast), Float(a.saturation), Float(a.vibrance), 0))
    }

    /// What a Tile of this frame has to carry, and where it may start. Measured against
    /// a Tile the size of the whole frame, so the Scattering Pyramids are as deep as
    /// they will ever be and both answers bound what any smaller Tile asks for.
    func tiling(profile: Profile, settings: RenderSettings, source: any MTLTexture,
                scatterFraction: Double) throws -> (apron: Int, alignment: Int) {
        let plan = try plan(profile: profile, settings: settings,
                            frame: Frame(width: source.width, height: source.height), tile: source, spatial: true)
        let scatter = Int((plan.scatterReach * min(max(scatterFraction, 0), 1)).rounded(.up))
        return (max(plan.exactReach, scatter), plan.alignment)
    }

    /// Film-Plane Microns become pixels through the Stock's Frame Width, which is the
    /// frame's long edge — a portrait photograph records it down its height.
    private static func pixelsPerMicron(_ profile: Profile, width: Int, height: Int) -> Double {
        Double(max(width, height)) / (profile.metadata.format.frameWidthMM * 1000)
    }

    /// The aperture ISO 10505 measures RMS granularity through. Selwyn's law makes
    /// granularity inversely proportional to the sampling aperture's diameter, so a
    /// Profile's single published figure sets the amplitude at every resolution.
    private static let granularityApertureMicrons = 48.0

    /// Resolves the Profile's Grain against this image, or nil when the Stock, the
    /// user or the Density Response leaves nothing to add.
    private func grain(profile: Profile, settings: RenderSettings, width: Int, height: Int,
                       base: SIMD3<Double>, gray: SIMD3<Double>, model: GrainModel) -> Grain? {
        let metadata = profile.metadata.grain
        guard settings.grainIntensity > 0, !metadata.isSilent,
              (0..<3).allSatisfy({ gray[$0] - base[$0] > 1e-4 }) else { return nil }
        let pixelsPerMicron = Self.pixelsPerMicron(profile, width: width, height: height)
        // What one pixel covers on the film. A frame that cannot resolve a crystal
        // still records its fluctuation; that is where Selwyn's law takes over from
        // the grain's own size, and it is why this is not a pixel-count scaling.
        let pitchMicrons = 1 / pixelsPerMicron
        var sigma = SIMD4<Float>(), cell = SIMD4<Float>()
        for channel in 0..<3 {
            let diameter = 2 * metadata.grainRadiusMicrons * metadata.channelRadiusScale[channel]
            let apertureMicrons = max(diameter, pitchMicrons)
            // Exactly one pixel when the frame cannot resolve the grain, so the shader
            // reads that as one independent sample rather than as a wide interpolation.
            cell[channel] = diameter > pitchMicrons ? Float(diameter * pixelsPerMicron) : 1
            sigma[channel] = Float(metadata.rmsGranularity * settings.grainIntensity
                                   * Self.granularityApertureMicrons / apertureMicrons)
        }
        // Variance-preserving split between a channel's own field and the one all
        // three share, so `channelCorrelation` reads as the correlation it names.
        let correlation = metadata.channelCorrelation
        let sharedDiameter = 2 * metadata.grainRadiusMicrons
        let sharedCell = sharedDiameter > pitchMicrons ? Float(sharedDiameter * pixelsPerMicron) : 1
        // Density Space takes the fluctuation directly; a Colour Cube carrying the
        // Baker's scan has already returned a positive, so it is a transmission there.
        let densitySpace = profile.metadata.colour.cubeOutput != .displayLinearRec2020
        var scale = SIMD4<Float>()
        for channel in 0..<3 { scale[channel] = Float(0.5 / (gray[channel] - base[channel])) }
        let uniforms = GrainUniforms(sigma: sigma, cell: cell,
                                     mix: SIMD4(Float((1 - correlation).squareRoot()), Float(correlation.squareRoot()),
                                                sharedCell, densitySpace ? 1 : 0),
                                     base: SIMD4(Float(base.x), Float(base.y), Float(base.z), 0),
                                     scale: scale, seed: SIMD4(repeating: settings.seed))
        return Grain(uniforms: uniforms, response: metadata.densityResponse.map(Float.init), model: model)
    }

    /// Fits the Profile's published MTF with two Gaussians and the signal itself.
    /// A Gaussian blur of sigma s has frequency response exp(−2π²s²f²), so the three
    /// together span both a roll-off and the adjacency effect that lifts a curve
    /// above one. Published points above Nyquist are dropped rather than fitted:
    /// a frame that cannot carry 80 cycles per millimetre has nothing to say there.
    private func mtf(profile: Profile, width: Int, height: Int) -> MTF? {
        let metadata = profile.metadata.mtf
        let pixelsPerMM = Self.pixelsPerMicron(profile, width: width, height: height) * 1000
        let points = zip(metadata.cyclesPerMM, metadata.response)
            .map { (cycles: $0 / pixelsPerMM, response: $1) }
            .filter { $0.cycles > 0 && $0.cycles <= 0.5 }
        guard let lowest = points.map(\.cycles).min(), let highest = points.map(\.cycles).max(),
              points.contains(where: { abs($0.response - 1) > 0.005 }) else { return nil }
        // The shader convolves a truncated, sampled Gaussian, whose response departs
        // from the continuous exp(−2π²s²f²) below about one pixel of sigma. Fitting
        // the kernel that actually runs is what keeps the rendered curve on the
        // published one; a sigma under 0.8 also has too little reach to attenuate
        // anything, so the fine Gaussian is held at least that wide.
        let fine = max(1 / (2 * .pi * highest), 0.8)
        let coarse = min(max(1 / (2 * .pi * lowest), 2 * fine), 16)
        func radius(_ sigma: Double) -> Int { min(24, max(1, Int((3 * sigma).rounded(.up)))) }
        func response(_ sigma: Double, _ cycles: Double) -> Double {
            var sum = 0.0, total = 0.0
            for tap in -radius(sigma)...radius(sigma) {
                let weight = exp(-0.5 * Double(tap * tap) / (sigma * sigma))
                sum += weight * cos(2 * .pi * cycles * Double(tap))
                total += weight
            }
            return sum / total
        }
        // Least squares on the two blur weights, with the direct weight taking the
        // remainder so the fit cannot change a flat field's value. A little Tikhonov
        // keeps a Profile with one usable point from being under-determined.
        var aa = 1e-3, ab = 0.0, bb = 1e-3, ay = 0.0, by = 0.0
        for point in points {
            let a = response(fine, point.cycles) - 1, b = response(coarse, point.cycles) - 1, y = point.response - 1
            aa += a * a; ab += a * b; bb += b * b; ay += a * y; by += b * y
        }
        let determinant = aa * bb - ab * ab
        var weights = SIMD2<Double>(ay / aa, 0)
        if abs(determinant) > 1e-9 { weights = SIMD2((ay * bb - by * ab) / determinant, (by * aa - ay * ab) / determinant) }
        weights = simd_clamp(weights, SIMD2(repeating: -4), SIMD2(repeating: 4))
        guard weights.x.isFinite, weights.y.isFinite else { return nil }
        return MTF(coefficients: SIMD4(Float(1 - weights.x - weights.y), Float(weights.x), Float(weights.y), 0),
                   fine: SIMD2(Float(fine), Float(radius(fine))), coarse: SIMD2(Float(coarse), Float(radius(coarse))))
    }

    /// Everything in the frame whose value depends on where in the frame it is.
    private func geometry(profile: Profile, settings: RenderSettings, width: Int, height: Int) -> Geometry? {
        guard settings.vignette > 0 || settings.gateWeave > 0 || settings.frameBorder > 0 else { return nil }
        let pixelsPerMicron = Self.pixelsPerMicron(profile, width: width, height: height)
        // A worn gate lets the frame wander a fraction of a millimetre; 200 µm is a
        // visibly unsteady projector and the top of the control. The displacement is
        // fixed by the seed, because a still frame weaves once rather than shimmering.
        var hash = settings.seed &* 0x9E37_79B9 &+ 0x85EB_CA6B
        func phase() -> Double {
            hash ^= hash >> 15; hash = hash &* 0x2C1B_3C6D; hash ^= hash >> 12; hash = hash &* 0x297A_2D39; hash ^= hash >> 15
            return Double(hash) / Double(UInt32.max) * 2 - 1
        }
        let excursion = settings.gateWeave * 200 * pixelsPerMicron
        // 1.5 mm of unexposed rebate alongside a 36 mm frame at the full setting.
        let border = settings.frameBorder * 1500 * pixelsPerMicron
        return Geometry(vignette: Float(settings.vignette),
                        weave: SIMD2(Float(phase() * excursion), Float(phase() * excursion)), border: Float(border))
    }

    /// The Scattering Pyramid a Bloom or Halation Pass blurs in, kept between renders
    /// because a Preview re-renders the same dimensions on every parameter change.
    private struct Pyramid {
        /// The thresholded light before any blur: the pyramid's zero-sigma level, so a
        /// radius finer than the smallest level's blur still resolves instead of clamping.
        let raw: any MTLTexture
        let levels: [any MTLTexture]
        let scratch: [any MTLTexture]
        var count: Int { levels.count }
    }

    /// The pyramid is only as deep as the widest requested radius needs: five or six
    /// levels at photographic sizes, fewer for a small Preview, and more only when a
    /// full-resolution frame asks for a halo six could not carry. Nine levels reach a
    /// 449-pixel sigma; beyond that the radius clamps.
    private static let maximumScatterLevels = 9

    /// Effective Gaussian sigma of the unblurred extract and of each level, in level-0
    /// pixels: that level's own blur plus every downsample and blur that produced it.
    private static let scatterLevelSigmas: [Double] = {
        let blur = 1.5
        var variance = blur * blur
        var sigmas = [0, variance.squareRoot()]
        for level in 1..<maximumScatterLevels {
            let scale = pow(2.0, Double(level))
            variance += pow(0.5 * scale / 2, 2) + pow(blur * scale, 2)
            sigmas.append(variance.squareRoot())
        }
        return sigmas
    }()

    /// The lens spreads a fraction of all the light across the frame, so Bloom has no
    /// threshold, no tint and one radius, and replaces what it takes rather than adding
    /// to it. Nil when the modelled lens or the user has nothing to diffuse.
    private func bloom(profile: Profile, settings: RenderSettings, frame: Frame, tile: any MTLTexture) -> Scatter? {
        let metadata = profile.metadata.bloom
        // Keep 0...100% faithful to the lens. Above the detent, open up a
        // useful diffusion range even for stocks whose baseline is only 2%.
        let boost = max(0, settings.bloomIntensity - 1)
        let strength = min(1, metadata.strength * settings.bloomIntensity
                           + max(0, 0.3 - 2 * metadata.strength) * boost * boost)
        guard metadata.strength > 0, strength > 0, metadata.radiusMicrons > 0 else { return nil }
        // A zero threshold with the narrowest knee takes every positive value: light a
        // lens cannot have received is not light it can diffuse.
        return scatter(profile: profile, radiusMicrons: [Double](repeating: metadata.radiusMicrons, count: 3),
                       parameters: SIMD4(0, 1e-4, Float(strength), 1), tint: [1, 1, 1], frame: frame, tile: tile)
    }

    /// Resolves the Profile's Film-Plane Micron radii against this image, or nil when
    /// the Stock or the user has no Halation to add.
    private func halation(profile: Profile, settings: RenderSettings, frame: Frame, tile: any MTLTexture) -> Scatter? {
        let metadata = profile.metadata.halation
        let boost = max(0, settings.halationIntensity - 1)
        let strength = metadata.strength * settings.halationIntensity
            + max(0, 0.3 - 2 * metadata.strength) * boost * boost
        guard metadata.strength > 0, strength > 0, metadata.radiusMicrons.contains(where: { $0 > 0 }) else { return nil }
        // SDR photos top out near 1 in linear light. The stock threshold
        // (often 1.6) otherwise leaves almost nothing to scatter even at 200%.
        // The creative range reaches those highlights without lifting exposure.
        let threshold = metadata.threshold + (min(metadata.threshold, 0.4) - metadata.threshold) * boost * boost
        return scatter(profile: profile, radiusMicrons: metadata.radiusMicrons,
                       parameters: SIMD4(Float(threshold), Float(max(threshold / 2, 1e-4)), Float(strength), 0),
                       tint: metadata.tint, frame: frame, tile: tile)
    }

    /// Splits each channel's requested radius across the pyramid's levels. Film-Plane
    /// Microns become pixels through the Stock's Frame Width, so what is scattered
    /// covers the same fraction of the frame at any resolution.
    private func scatter(profile: Profile, radiusMicrons: [Double], parameters: SIMD4<Float>,
                         tint: [Double], frame: Frame, tile: any MTLTexture) -> Scatter {
        let pixelsPerMicron = Self.pixelsPerMicron(profile, width: frame.width, height: frame.height)
        let largest = radiusMicrons.max()! * pixelsPerMicron
        // Deep enough for the widest channel, and never deeper than the Tile allows:
        // a level that collapsed to a single texel would carry no radius at all. The
        // radius above comes from the frame and the depth cap here from the Tile,
        // which is what keeps a Tile's halo the same size as the untiled one's.
        let reach = Self.scatterLevelSigmas.firstIndex { $0 >= largest } ?? Self.maximumScatterLevels
        let count = min(max(reach, 1), max(1, Int(log2(Double(min(tile.width, tile.height))))))
        let sigmas = Array(Self.scatterLevelSigmas.prefix(count + 1))
        var weights = [SIMD4<Float>](repeating: .zero, count: count + 1)
        for channel in 0..<3 {
            let sigma = radiusMicrons[channel] * pixelsPerMicron
            if sigma >= sigmas[count] {
                weights[count][channel] = 1
            } else {
                // Split across the two neighbouring levels so the mixture carries the
                // requested variance. Level scale is geometric, so weighting by variance
                // keeps the radius continuous in image size rather than jumping level.
                let lower = (0..<count).last { sigmas[$0] <= sigma } ?? 0
                let finer = sigmas[lower] * sigmas[lower], coarser = sigmas[lower + 1] * sigmas[lower + 1]
                let fraction = (sigma * sigma - finer) / (coarser - finer)
                weights[lower][channel] = Float(1 - fraction)
                weights[lower + 1][channel] = Float(fraction)
            }
        }
        // Weight 0 belongs to the unblurred extract, so weight index i is level i − 1.
        let top = weights.lastIndex { weight in (0..<3).contains { weight[$0] != 0 } } ?? 0
        return Scatter(parameters: parameters, tint: SIMD4(Float(tint[0]), Float(tint[1]), Float(tint[2]), 0),
                       levelWeights: weights, topLevel: top > 0 ? top - 1 : nil)
    }

    private func pyramid(_ scattering: Scattering, width: Int, height: Int, count: Int) throws -> Pyramid {
        if let pyramid = pyramids[scattering], pyramid.count == count,
           pyramid.levels[0].width == width, pyramid.levels[0].height == height { return pyramid }
        var levels: [any MTLTexture] = []
        var scratch: [any MTLTexture] = []
        for level in 0..<count {
            // Rounded up, so a level always covers the whole extent below it. Rounding
            // down leaves the last row and column of the finer level unrepresented,
            // which a Tile reads as its own edge and an untiled render does not.
            let w = max(1, (width + (1 << level) - 1) >> level)
            let h = max(1, (height + (1 << level) - 1) >> level)
            levels.append(try decoder.makeTexture(width: w, height: h))
            scratch.append(try decoder.makeTexture(width: w, height: h))
        }
        let pyramid = Pyramid(raw: try decoder.makeTexture(width: width, height: height), levels: levels, scratch: scratch)
        pyramids[scattering] = pyramid
        return pyramid
    }

    /// Threshold, blur each level, then accumulate coarse to fine and composite the
    /// tinted result back into the linear signal the Film Response reads.
    private func encodeScatter(_ scatter: Scatter, _ scattering: Scattering, command: any MTLCommandBuffer,
                               source: any MTLTexture, destination: any MTLTexture) throws {
        let pyramid = try pyramid(scattering, width: source.width, height: source.height,
                                  count: scatter.levelWeights.count - 1)
        var parameters = scatter.parameters
        var tint = scatter.tint
        func dispatch(_ name: String, label: String, textures: [any MTLTexture], weight: SIMD4<Float>? = nil,
                      grid: any MTLTexture) throws {
            guard let encoder = command.makeComputeCommandEncoder(), let pipeline = pipelines[name] else {
                throw FilmError.invalid("Cannot encode \(label)")
            }
            encoder.label = label
            encoder.setComputePipelineState(pipeline)
            for (index, texture) in textures.enumerated() { encoder.setTexture(texture, index: index) }
            encoder.setBytes(&parameters, length: MemoryLayout<SIMD4<Float>>.size, index: 8)
            encoder.setBytes(&tint, length: MemoryLayout<SIMD4<Float>>.size, index: 9)
            var levelWeight = weight ?? .zero
            encoder.setBytes(&levelWeight, length: MemoryLayout<SIMD4<Float>>.size, index: 10)
            encoder.dispatchThreads(MTLSize(width: grid.width, height: grid.height, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            encoder.endEncoding()
        }
        // Weight 0 belongs to the unblurred extract; weight L + 1 to pyramid level L.
        try dispatch("scatterThreshold", label: "\(scattering).threshold", textures: [source, pyramid.raw], grid: pyramid.raw)
        for level in 0..<pyramid.count {
            let input = level == 0 ? pyramid.raw : pyramid.levels[level]
            try dispatch("scatterBlurHorizontal", label: "\(scattering).blurH.\(level)",
                         textures: [input, pyramid.scratch[level]], grid: pyramid.levels[level])
            try dispatch("scatterBlurVertical", label: "\(scattering).blurV.\(level)",
                         textures: [pyramid.scratch[level], pyramid.levels[level]], grid: pyramid.levels[level])
            if level + 1 < pyramid.count {
                try dispatch("scatterDownsample", label: "\(scattering).downsample.\(level + 1)",
                             textures: [pyramid.levels[level], pyramid.levels[level + 1]], grid: pyramid.levels[level + 1])
            }
        }
        let top = pyramid.count - 1
        try dispatch("scatterScale", label: "\(scattering).scale.\(top)", textures: [pyramid.levels[top], pyramid.scratch[top]],
                     weight: scatter.levelWeights[top + 1], grid: pyramid.levels[top])
        for level in stride(from: top - 1, through: 0, by: -1) {
            try dispatch("scatterUpsample", label: "\(scattering).upsample.\(level)",
                         textures: [pyramid.scratch[level + 1], pyramid.levels[level], pyramid.scratch[level]],
                         weight: scatter.levelWeights[level + 1], grid: pyramid.levels[level])
        }
        try dispatch("scatterComposite", label: "\(scattering).composite",
                     textures: [source, destination, pyramid.scratch[0], pyramid.raw],
                     weight: scatter.levelWeights[0], grid: destination)
    }

    /// Two separable Gaussians of the source, combined with the source itself. The
    /// three textures are kept between renders for the same reason the Halation
    /// pyramid is: a Preview re-renders the same dimensions on every change.
    private func mtfTextures(width: Int, height: Int) throws -> [any MTLTexture] {
        if let textures = mtfTextures, textures[0].width == width, textures[0].height == height { return textures }
        let textures = try (0..<3).map { _ in try decoder.makeTexture(width: width, height: height) }
        mtfTextures = textures
        return textures
    }

    private func encodeMTF(_ mtf: MTF, command: any MTLCommandBuffer,
                           source: any MTLTexture, destination: any MTLTexture) throws {
        let textures = try mtfTextures(width: source.width, height: source.height)
        func blur(_ gaussian: SIMD2<Float>, into result: any MTLTexture, label: String) throws {
            for (index, axis) in [SIMD2<Float>(1, 0), SIMD2<Float>(0, 1)].enumerated() {
                var parameters = SIMD4<Float>(gaussian.x, gaussian.y, axis.x, axis.y)
                try dispatch("mtfBlur", label: "\(label).\(index == 0 ? "h" : "v")",
                             textures: [(index == 0 ? source : textures[2], 0), (index == 0 ? textures[2] : result, 1)],
                             command: command, grid: result) { $0.setBytes(&parameters, length: MemoryLayout<SIMD4<Float>>.size, index: 14) }
            }
        }
        try blur(mtf.fine, into: textures[0], label: "mtf.fine")
        try blur(mtf.coarse, into: textures[1], label: "mtf.coarse")
        var coefficients = mtf.coefficients
        try dispatch("mtfCombine", label: "mtf.combine",
                     textures: [(source, 0), (destination, 1), (textures[0], 4), (textures[1], 5)],
                     command: command, grid: destination) { $0.setBytes(&coefficients, length: MemoryLayout<SIMD4<Float>>.size, index: 14) }
    }

    /// The Grain and Geometry Passes are the two whose value depends on *where* in the
    /// frame a pixel sits, so both are given the Tile's placement in it.
    private func encodeGrain(_ grain: Grain, frame: inout SIMD4<Float>, command: any MTLCommandBuffer,
                             source: any MTLTexture, destination: any MTLTexture) throws {
        var uniforms = grain.uniforms
        // `dye-cloud` has its own kernel; `stochastic` is still MEM-239's phase 7 and
        // resolves here to the procedural one that exists.
        try dispatch(grain.model == .dyeCloud ? "grainDyeCloud" : "grain",
                     label: "\(Pass.grain.rawValue).\(grain.model.rawValue)",
                     textures: [(source, 0), (destination, 1)],
                     command: command, grid: destination) {
            $0.setBytes(&uniforms, length: MemoryLayout<GrainUniforms>.stride, index: 11)
            $0.setBytes(grain.response, length: MemoryLayout<Float>.stride * grain.response.count, index: 12)
            $0.setBytes(&frame, length: MemoryLayout<SIMD4<Float>>.size, index: 17)
        }
    }

    private func encodeGeometry(_ geometry: Geometry, frame: inout SIMD4<Float>, command: any MTLCommandBuffer,
                                source: any MTLTexture, destination: any MTLTexture) throws {
        var parameters = geometry.packed
        try dispatch("geometry", label: Pass.geometry.rawValue, textures: [(source, 0), (destination, 1)],
                     command: command, grid: destination) {
            $0.setBytes(&parameters, length: MemoryLayout<SIMD4<Float>>.size, index: 16)
            $0.setBytes(&frame, length: MemoryLayout<SIMD4<Float>>.size, index: 17)
        }
    }

    private func dispatch(_ name: String, label: String, textures: [(any MTLTexture, Int)],
                          command: any MTLCommandBuffer, grid: any MTLTexture,
                          bind: (any MTLComputeCommandEncoder) -> Void) throws {
        guard let encoder = command.makeComputeCommandEncoder(), let pipeline = pipelines[name] else {
            throw FilmError.invalid("Cannot encode \(label)")
        }
        encoder.label = label
        encoder.setComputePipelineState(pipeline)
        for (texture, index) in textures { encoder.setTexture(texture, index: index) }
        bind(encoder)
        encoder.dispatchThreads(MTLSize(width: grid.width, height: grid.height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        encoder.endEncoding()
    }

    private func pipelineName(for pass: Pass, plan: Plan, profile: Profile) -> String {
        switch pass {
        case .whiteBalance: plan.whiteBalance == nil ? "passthrough" : "whiteBalance"
        case .exposure: plan.gain == 1 ? "passthrough" : "exposure"
        case .reciprocity: plan.reciprocity == nil ? "passthrough" : "reciprocity"
        case .filmResponse: profile.metadata.process.isMonochrome ? "monochromeResponse" : "filmResponse"
        case .outputStage: plan.scan ? "scanOutput" : "passthrough"
        case .adjust: plan.adjustments == nil ? "passthrough" : "adjust"
        case .outputTransform: "outputTransform"
        default: "passthrough"
        }
    }

    func readback(_ texture: any MTLTexture) throws -> LinearImage {
        let count = texture.width * texture.height * 4
        let rgba = [Float16](unsafeUninitializedCapacity: count) { buffer, initialized in
            texture.getBytes(buffer.baseAddress!, bytesPerRow: texture.width * 8,
                             from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
            initialized = count
        }
        return LinearImage(unchecked: texture.width, texture.height, rgba)
    }

    private func responseEntry(for profile: Profile, name: String?) throws -> ResponseEntry {
        guard let name else { throw FilmError.invalid("Profile has no Film Response payload") }
        if let index = responseCache.firstIndex(where: { $0.id == profile.cacheID && $0.name == name }) {
            let entry = responseCache.remove(at: index)
            responseCache.append(entry)
            return entry
        }
        let payload = try profile.readPayload(name)
        let entry: ResponseEntry
        if profile.metadata.monochrome != nil {
            let values = try decodeHalfValues(payload)
            guard values.count == 1024 else { throw FilmError.invalid("Density Curve must contain 1024 entries") }
            let descriptor = MTLTextureDescriptor()
            descriptor.textureType = .type1D
            descriptor.pixelFormat = .r16Float
            descriptor.width = 1024
            descriptor.usage = .shaderRead
            descriptor.storageMode = .shared
            guard let curve = device.makeTexture(descriptor: descriptor) else { throw FilmError.invalid("Cannot allocate Density Curve") }
            values.withUnsafeBytes {
                curve.replace(region: MTLRegionMake1D(0, 1024), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 2048)
            }
            // The collapse's weights sum to one, so mid-grey light collapses to mid-grey
            // whichever Contrast Filter is on, and the scan's reference is the same
            // point of the Density Curve for all of them.
            let position = Self.responseCoordinate(0.18, shaper: profile.metadata.colour.inputShaper) * 1023
            let low = min(Int(position), 1022)
            let gray = Double(values[low]) + (position - Double(low)) * (Double(values[low + 1]) - Double(values[low]))
            let blackPoint = Self.responseCoordinate(0, shaper: profile.metadata.colour.inputShaper) * 1023
            let base = Double(values[min(Int(blackPoint), 1023)])
            entry = ResponseEntry(id: profile.cacheID, name: name, texture: curve, grayDensity: SIMD3(repeating: gray),
                                  baseDensity: SIMD3(repeating: base))
        } else {
            let cube = try ColourCube(size: profile.metadata.colour.lutSize, payload: payload)
            entry = ResponseEntry(id: profile.cacheID, name: name, texture: try makeColourCube(cube),
                                  grayDensity: cube.sample(SIMD3(repeating: 0.18)), baseDensity: cube.sample(SIMD3(repeating: 0)))
        }
        responseCache.append(entry)
        if responseCache.count > textureCacheCapacity { responseCache.removeFirst() }
        return entry
    }

    /// Where scene-linear grey lands in a Density Curve, in [0, 1]. A Curve Set with
    /// no shaper addresses the curve by linear light, as the foundation studies do; a
    /// measured one addresses it in physical log exposure, exactly as the shader does.
    static func responseCoordinate(_ light: Double, shaper: FilmProfile.LogExposureShaper?) -> Double {
        guard let shaper else { return min(max(light, 0), 1) }
        let logH = log10(max(light, 1e-6) / 0.18) + shaper.middleGrayLogExposure
        return min(max((logH - shaper.minimumLogExposure) / (shaper.maximumLogExposure - shaper.minimumLogExposure), 0), 1)
    }

    private func makeColourCube(_ cube: ColourCube) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba16Float
        descriptor.width = cube.size; descriptor.height = cube.size; descriptor.depth = cube.size
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw FilmError.invalid("Cannot allocate Colour Cube") }
        cube.rgba.withUnsafeBytes {
            texture.replace(region: MTLRegionMake3D(0, 0, 0, cube.size, cube.size, cube.size), mipmapLevel: 0, slice: 0,
                withBytes: $0.baseAddress!, bytesPerRow: cube.size * 8, bytesPerImage: cube.size * cube.size * 8)
        }
        return texture
    }
}

/// The thirteen-stage pipeline, in the order the light meets it. Bloom is the taking
/// lens and so precedes Halation, which happens inside the film; the Adjustment
/// Pass follows the Output Stage because it is work done to the scan afterwards.
private enum Pass: String, CaseIterable {
    case decode, whiteBalance, exposure, reciprocity, bloom, halation, mtf, filmResponse, grain,
         outputStage, adjust, geometry, outputTransform
}
