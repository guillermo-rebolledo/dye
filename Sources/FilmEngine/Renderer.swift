import Foundation
import Metal

/// Owns its command queue and resources; callers can render off the main actor.
public actor Renderer {
    private let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let pipelines: [String: any MTLComputePipelineState]
    private let decoder: ImageDecoder
    private let textureCacheCapacity: Int
    private var responseCache: [(id: UUID, name: String, texture: any MTLTexture)] = []

    public init(textureCacheCapacity: Int = 3) throws {
        guard (1...32).contains(textureCacheCapacity) else { throw FilmError.invalid("Texture cache capacity must be 1...32") }
        self.textureCacheCapacity = textureCacheCapacity
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw FilmError.invalid("Metal is unavailable")
        }
        self.device = device
        self.queue = queue
        decoder = ImageDecoder(device: device)
        let url = Bundle.module.url(forResource: "Pipeline", withExtension: "metal", subdirectory: "Metal")!
        let options = MTLCompileOptions()
        if #available(macOS 15, iOS 18, *) { options.mathMode = .safe }
        else { options.fastMathEnabled = false }
        let library = try device.makeLibrary(source: String(contentsOf: url, encoding: .utf8), options: options)
        var pipelines: [String: any MTLComputePipelineState] = [:]
        for name in ["passthrough", "filmResponse", "monochromeResponse", "outputTransform"] {
            guard let function = library.makeFunction(name: name) else { throw FilmError.invalid("Missing shader \(name)") }
            pipelines[name] = try device.makeComputePipelineState(function: function)
        }
        self.pipelines = pipelines
    }

    /// The sole renderer test seam. Encoded input is colour-managed before Metal;
    /// linear input already belongs to the Working Space. All eleven passes run.
    public func render(image: RenderImage, profile: Profile, settings: RenderSettings = .init()) throws -> RenderedPixels {
        guard settings.developmentOffset.isFinite else { throw FilmError.invalid("Development Offset must be finite") }
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
        let response = try responseTexture(for: profile, developmentOffset: settings.developmentOffset)
        let scratch = try decoder.makeTexture(width: input.width, height: input.height)
        guard let command = queue.makeCommandBuffer() else { throw FilmError.invalid("Cannot create render command") }
        var source = input
        var destination = scratch
        for pass in Pass.allCases {
            let responseName = profile.metadata.process.isMonochrome ? "monochromeResponse" : "filmResponse"
            let name = pass == .filmResponse ? responseName : pass == .outputTransform ? "outputTransform" : "passthrough"
            guard let encoder = command.makeComputeCommandEncoder(), let pipeline = pipelines[name] else {
                throw FilmError.invalid("Cannot encode \(pass)")
            }
            encoder.label = pass.rawValue
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(source, index: 0)
            encoder.setTexture(destination, index: 1)
            encoder.setTexture(response, index: 2)
            let spectralWeight = profile.metadata.monochrome?.spectralWeight ?? [0, 0, 0]
            var weights = SIMD4<Float>(Float(spectralWeight[0]), Float(spectralWeight[1]), Float(spectralWeight[2]), 0)
            encoder.setBytes(&weights, length: MemoryLayout<SIMD4<Float>>.size, index: 1)
            var output = settings.output.rawValue
            encoder.setBytes(&output, length: MemoryLayout<UInt32>.size, index: 0)
            encoder.dispatchThreads(MTLSize(width: input.width, height: input.height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            encoder.endEncoding()
            swap(&source, &destination)
        }
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        var rgba = [Float16](repeating: 0, count: input.width * input.height * 4)
        rgba.withUnsafeMutableBytes {
            source.getBytes($0.baseAddress!, bytesPerRow: input.width * 8,
                            from: MTLRegionMake2D(0, 0, input.width, input.height), mipmapLevel: 0)
        }
        return RenderedPixels(width: input.width, height: input.height, rgba: rgba, output: settings.output)
    }

    private func responseTexture(for profile: Profile, developmentOffset: Double) throws -> any MTLTexture {
        let selected = profile.metadata.colour.lutVariants.min { abs($0.pushStops - developmentOffset) < abs($1.pushStops - developmentOffset) }
        guard let name = profile.metadata.monochrome?.densityCurve ?? selected?.lut else {
            throw FilmError.invalid("Profile has no Film Response payload")
        }
        if let index = responseCache.firstIndex(where: { $0.id == profile.cacheID && $0.name == name }) {
            let entry = responseCache.remove(at: index)
            responseCache.append(entry)
            return entry.texture
        }
        let payload = try profile.readPayload(name)
        let texture: any MTLTexture
        if profile.metadata.process.isMonochrome {
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
            texture = curve
        } else {
            texture = try makeColourCube(ColourCube(size: profile.metadata.colour.lutSize, payload: payload))
        }
        responseCache.append((profile.cacheID, name, texture))
        if responseCache.count > textureCacheCapacity { responseCache.removeFirst() }
        return texture
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
