import Foundation
import Metal
import simd

/// Owns its command queue and resources; callers can render off the main actor.
public actor Renderer {
    private let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let pipelines: [String: any MTLComputePipelineState]
    private let decoder: ImageDecoder
    private let textureCacheCapacity: Int
    private var responseCache: [ResponseEntry] = []
    private var halationPyramid: HalationPyramid?
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
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw FilmError.invalid("Metal is unavailable")
        }
        self.device = device
        self.queue = queue
        decoder = try ImageDecoder(device: device)
        let url = Bundle.module.url(forResource: "Pipeline", withExtension: "metal", subdirectory: "Metal")!
        let options = MTLCompileOptions()
        if #available(macOS 15, iOS 18, *) { options.mathMode = .safe }
        else { options.fastMathEnabled = false }
        let library = try device.makeLibrary(source: String(contentsOf: url, encoding: .utf8), options: options)
        var pipelines: [String: any MTLComputePipelineState] = [:]
        for name in ["passthrough", "whiteBalance", "exposure", "filmResponse", "monochromeResponse", "scanOutput", "outputTransform",
                     "halationThreshold", "halationDownsample", "halationBlurHorizontal", "halationBlurVertical",
                     "halationScale", "halationUpsample", "halationComposite",
                     "mtfBlur", "mtfCombine", "grain", "geometry"] {
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
    /// linear input already belongs to the Working Space. All eleven passes run.
    public func render(image: RenderImage, profile: Profile, settings: RenderSettings = .init()) throws -> RenderedPixels {
        try settings.validate()
        let input: any MTLTexture
        switch image {
        case .encoded(let data): input = try decoder.decode(data)
        case .linear(let image):
            input = try decoder.makeTexture(width: image.width, height: image.height)
            image.rgba.withUnsafeBytes {
                input.replace(region: MTLRegionMake2D(0, 0, image.width, image.height), mipmapLevel: 0,
                              withBytes: $0.baseAddress!, bytesPerRow: image.width * 8)
            }
        }
        let plan = try plan(profile: profile, settings: settings, width: input.width, height: input.height)
        let scratch = try decoder.makeTexture(width: input.width, height: input.height)
        guard let command = queue.makeCommandBuffer() else { throw FilmError.invalid("Cannot create render command") }
        var source = input
        var destination = scratch
        for pass in Pass.allCases {
            // Four passes need more than one dispatch, or resources of their own, so
            // they encode themselves rather than going through the loop below. A Pass
            // the Plan resolved to nil does not run at all, and releases whatever it
            // was holding: neither a Stock nor an intensity that will not use those
            // textures should keep them alive.
            if pass == .halation {
                guard let halation = plan.halation else { halationPyramid = nil; continue }
                try encodeHalation(halation, command: command, source: source, destination: destination)
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
                try encodeGrain(grain, command: command, source: source, destination: destination)
                swap(&source, &destination)
                continue
            }
            if pass == .geometry {
                guard let geometry = plan.geometry else { continue }
                try encodeGeometry(geometry, command: command, source: source, destination: destination)
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
            let spectralWeight = profile.metadata.monochrome?.spectralWeight ?? [0, 0, 0]
            var weights = SIMD4<Float>(Float(spectralWeight[0]), Float(spectralWeight[1]), Float(spectralWeight[2]), 0)
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
            encoder.dispatchThreads(MTLSize(width: input.width, height: input.height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            encoder.endEncoding()
            swap(&source, &destination)
        }
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        let result = try readback(source)
        return RenderedPixels(width: result.width, height: result.height, rgba: result.rgba, output: settings.output)
    }

    private struct Plan {
        let whiteBalance: simd_float3x3?
        let gain: Float
        let lower: ResponseEntry
        let upper: ResponseEntry?
        let blend: Float
        let shaper: SIMD4<Float>
        let scan: Bool
        let grayDensity: SIMD4<Float>
        let baseDensity: SIMD4<Float>
        let halation: Halation?
        let mtf: MTF?
        let grain: Grain?
        let geometry: Geometry?
    }

    /// Everything the Halation Pass needs, resolved against the image it will run on.
    private struct Halation {
        /// (threshold, knee half-width, strength × intensity, unused).
        let parameters: SIMD4<Float>
        let tint: SIMD4<Float>
        /// Per level, how much of that level each channel takes. Sums to one per channel.
        let levelWeights: [SIMD4<Float>]
    }

    /// The Stock's published response curve fitted to two Gaussians for this image.
    private struct MTF {
        /// (direct, fine, coarse, unused) weights summing to one.
        let coefficients: SIMD4<Float>
        /// (sigma, kernel radius) in pixels, for the fine and the coarse Gaussian.
        let fine: SIMD2<Float>
        let coarse: SIMD2<Float>
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
    }

    private func plan(profile: Profile, settings: RenderSettings, width: Int, height: Int) throws -> Plan {
        let metadata = profile.metadata
        let whiteBalance = WhiteBalance.matrix(sceneKelvin: settings.temperatureKelvin, tint: settings.tint, stockBalanceKelvin: metadata.balance)
        // Development Offsets are clamped to the baked range for both the Colour Cube
        // choice and the rating that goes with it. Between variants both blend linearly.
        let variants = metadata.colour.lutVariants.sorted { $0.pushStops < $1.pushStops }
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
        let gain = Float(pow(2, settings.exposureStops - offset))
        let lower = try responseEntry(for: profile, name: metadata.monochrome?.densityCurve ?? lowerVariant?.lut)
        let upper = try upperVariant.map { try responseEntry(for: profile, name: $0.lut) }
        var shaper = SIMD4<Float>(repeating: 0)
        if let s = metadata.colour.inputShaper {
            shaper = SIMD4(1, Float(s.minimumLogExposure), Float(1 / (s.maximumLogExposure - s.minimumLogExposure)), Float(s.middleGrayLogExposure))
        }
        let stage = settings.outputStage ?? metadata.colour.outputStage
        guard stage != .print else { throw FilmError.invalid("The Print Output Stage is not implemented yet") }
        // Spectral cubes already contain the Baker's scan; a Density Space cube is scanned here.
        let scan = stage == .scan && metadata.colour.cubeOutput != .displayLinearRec2020
        func blended(_ value: (ResponseEntry) -> SIMD3<Double>) -> SIMD3<Double> {
            value(lower) + (upper.map { (value($0) - value(lower)) * Double(blend) } ?? SIMD3(repeating: 0))
        }
        let gray = blended(\.grayDensity), base = blended(\.baseDensity)
        if scan, (0..<3).contains(where: { gray[$0] - base[$0] < 0.001 }) {
            throw FilmError.invalid("Profile \(metadata.id): mid-grey density is not above base density; the scan cannot auto-balance")
        }
        return Plan(whiteBalance: whiteBalance, gain: gain, lower: lower, upper: upper, blend: blend, shaper: shaper, scan: scan,
                    grayDensity: SIMD4(Float(gray.x), Float(gray.y), Float(gray.z), scan ? 1 : 0),
                    baseDensity: SIMD4(Float(base.x), Float(base.y), Float(base.z), 0),
                    halation: halation(profile: profile, settings: settings, width: width, height: height),
                    mtf: mtf(profile: profile, width: width, height: height),
                    grain: grain(profile: profile, settings: settings, width: width, height: height, base: base, gray: gray),
                    geometry: geometry(profile: profile, settings: settings, width: width, height: height))
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
                       base: SIMD3<Double>, gray: SIMD3<Double>) -> Grain? {
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
        return Grain(uniforms: uniforms, response: metadata.densityResponse.map(Float.init))
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

    /// The pyramid the Halation Pass blurs in, kept between renders because a
    /// Preview re-renders the same dimensions on every parameter change.
    private struct HalationPyramid {
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
    private static let maximumHalationLevels = 9

    /// Effective Gaussian sigma of the unblurred extract and of each level, in level-0
    /// pixels: that level's own blur plus every downsample and blur that produced it.
    private static let halationLevelSigmas: [Double] = {
        let blur = 1.5
        var variance = blur * blur
        var sigmas = [0, variance.squareRoot()]
        for level in 1..<maximumHalationLevels {
            let scale = pow(2.0, Double(level))
            variance += pow(0.5 * scale / 2, 2) + pow(blur * scale, 2)
            sigmas.append(variance.squareRoot())
        }
        return sigmas
    }()

    /// Resolves the Profile's Film-Plane Micron radii against this image, or nil when
    /// the Stock or the user has no Halation to add.
    private func halation(profile: Profile, settings: RenderSettings, width: Int, height: Int) -> Halation? {
        let metadata = profile.metadata.halation
        let strength = metadata.strength * settings.halationIntensity
        guard strength > 0, metadata.radiusMicrons.contains(where: { $0 > 0 }) else { return nil }
        // Film-Plane Microns become pixels through the Stock's Frame Width, so the halo
        // covers the same fraction of the frame at any resolution.
        let pixelsPerMicron = Self.pixelsPerMicron(profile, width: width, height: height)
        let largest = metadata.radiusMicrons.max()! * pixelsPerMicron
        // Deep enough for the widest channel, and never deeper than the image allows:
        // a level that collapsed to a single texel would carry no radius at all.
        let reach = Self.halationLevelSigmas.firstIndex { $0 >= largest } ?? Self.maximumHalationLevels
        let count = min(max(reach, 1), max(1, Int(log2(Double(min(width, height))))))
        let sigmas = Array(Self.halationLevelSigmas.prefix(count + 1))
        var weights = [SIMD4<Float>](repeating: .zero, count: count + 1)
        for channel in 0..<3 {
            let sigma = metadata.radiusMicrons[channel] * pixelsPerMicron
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
        let threshold = metadata.threshold
        return Halation(parameters: SIMD4(Float(threshold), Float(max(threshold / 2, 1e-4)), Float(strength), 0),
                        tint: SIMD4(Float(metadata.tint[0]), Float(metadata.tint[1]), Float(metadata.tint[2]), 0),
                        levelWeights: weights)
    }

    private func halationPyramid(width: Int, height: Int, count: Int) throws -> HalationPyramid {
        if let pyramid = halationPyramid, pyramid.count == count,
           pyramid.levels[0].width == width, pyramid.levels[0].height == height { return pyramid }
        var levels: [any MTLTexture] = []
        var scratch: [any MTLTexture] = []
        for level in 0..<count {
            let w = max(1, width >> level), h = max(1, height >> level)
            levels.append(try decoder.makeTexture(width: w, height: h))
            scratch.append(try decoder.makeTexture(width: w, height: h))
        }
        let pyramid = HalationPyramid(raw: try decoder.makeTexture(width: width, height: height), levels: levels, scratch: scratch)
        halationPyramid = pyramid
        return pyramid
    }

    /// Threshold, blur each level, then accumulate coarse to fine and composite the
    /// tinted result back into the linear signal the Film Response reads.
    private func encodeHalation(_ halation: Halation, command: any MTLCommandBuffer,
                                source: any MTLTexture, destination: any MTLTexture) throws {
        let pyramid = try halationPyramid(width: source.width, height: source.height, count: halation.levelWeights.count - 1)
        var parameters = halation.parameters
        var tint = halation.tint
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
        try dispatch("halationThreshold", label: "halation.threshold", textures: [source, pyramid.raw], grid: pyramid.raw)
        for level in 0..<pyramid.count {
            let input = level == 0 ? pyramid.raw : pyramid.levels[level]
            try dispatch("halationBlurHorizontal", label: "halation.blurH.\(level)",
                         textures: [input, pyramid.scratch[level]], grid: pyramid.levels[level])
            try dispatch("halationBlurVertical", label: "halation.blurV.\(level)",
                         textures: [pyramid.scratch[level], pyramid.levels[level]], grid: pyramid.levels[level])
            if level + 1 < pyramid.count {
                try dispatch("halationDownsample", label: "halation.downsample.\(level + 1)",
                             textures: [pyramid.levels[level], pyramid.levels[level + 1]], grid: pyramid.levels[level + 1])
            }
        }
        let top = pyramid.count - 1
        try dispatch("halationScale", label: "halation.scale.\(top)", textures: [pyramid.levels[top], pyramid.scratch[top]],
                     weight: halation.levelWeights[top + 1], grid: pyramid.levels[top])
        for level in stride(from: top - 1, through: 0, by: -1) {
            try dispatch("halationUpsample", label: "halation.upsample.\(level)",
                         textures: [pyramid.scratch[level + 1], pyramid.levels[level], pyramid.scratch[level]],
                         weight: halation.levelWeights[level + 1], grid: pyramid.levels[level])
        }
        try dispatch("halationComposite", label: "halation.composite",
                     textures: [source, destination, pyramid.scratch[0], pyramid.raw],
                     weight: halation.levelWeights[0], grid: destination)
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

    private func encodeGrain(_ grain: Grain, command: any MTLCommandBuffer,
                             source: any MTLTexture, destination: any MTLTexture) throws {
        var uniforms = grain.uniforms
        try dispatch("grain", label: Pass.grain.rawValue, textures: [(source, 0), (destination, 1)],
                     command: command, grid: destination) {
            $0.setBytes(&uniforms, length: MemoryLayout<GrainUniforms>.stride, index: 11)
            $0.setBytes(grain.response, length: MemoryLayout<Float>.stride * grain.response.count, index: 12)
        }
    }

    private func encodeGeometry(_ geometry: Geometry, command: any MTLCommandBuffer,
                                source: any MTLTexture, destination: any MTLTexture) throws {
        var parameters = geometry.packed
        try dispatch("geometry", label: Pass.geometry.rawValue, textures: [(source, 0), (destination, 1)],
                     command: command, grid: destination) {
            $0.setBytes(&parameters, length: MemoryLayout<SIMD4<Float>>.size, index: 16)
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
        case .filmResponse: profile.metadata.process.isMonochrome ? "monochromeResponse" : "filmResponse"
        case .outputStage: plan.scan ? "scanOutput" : "passthrough"
        case .outputTransform: "outputTransform"
        default: "passthrough"
        }
    }

    private func readback(_ texture: any MTLTexture) throws -> LinearImage {
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
        if let monochrome = profile.metadata.monochrome {
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
            let position = min(max(0.18 * monochrome.spectralWeight.reduce(0, +), 0), 1) * 1023
            let low = min(Int(position), 1022)
            let gray = Double(values[low]) + (position - Double(low)) * (Double(values[low + 1]) - Double(values[low]))
            entry = ResponseEntry(id: profile.cacheID, name: name, texture: curve, grayDensity: SIMD3(repeating: gray),
                                  baseDensity: SIMD3(repeating: Double(values[0])))
        } else {
            let cube = try ColourCube(size: profile.metadata.colour.lutSize, payload: payload)
            entry = ResponseEntry(id: profile.cacheID, name: name, texture: try makeColourCube(cube),
                                  grayDensity: cube.sample(SIMD3(repeating: 0.18)), baseDensity: cube.sample(SIMD3(repeating: 0)))
        }
        responseCache.append(entry)
        if responseCache.count > textureCacheCapacity { responseCache.removeFirst() }
        return entry
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

private enum Pass: String, CaseIterable {
    case decode, whiteBalance, exposure, reciprocity, halation, mtf, filmResponse, grain, outputStage, geometry, outputTransform
}
