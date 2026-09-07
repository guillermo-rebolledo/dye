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
        for name in ["passthrough", "whiteBalance", "exposure", "filmResponse", "monochromeResponse", "scanOutput", "outputTransform"] {
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
        let plan = try plan(profile: profile, settings: settings)
        let scratch = try decoder.makeTexture(width: input.width, height: input.height)
        guard let command = queue.makeCommandBuffer() else { throw FilmError.invalid("Cannot create render command") }
        var source = input
        var destination = scratch
        for pass in Pass.allCases {
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
    }

    private func plan(profile: Profile, settings: RenderSettings) throws -> Plan {
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
                    baseDensity: SIMD4(Float(base.x), Float(base.y), Float(base.z), 0))
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
