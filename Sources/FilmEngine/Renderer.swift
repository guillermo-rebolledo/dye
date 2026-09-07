import Foundation
import Metal

/// Owns its command queue and resources; callers can render off the main actor.
public actor Renderer {
    private let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let pipelines: [String: any MTLComputePipelineState]
    private let decoder: ImageDecoder

    public init() throws {
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
        for name in ["passthrough", "filmResponse", "outputTransform"] {
            guard let function = library.makeFunction(name: name) else { throw FilmError.invalid("Missing shader \(name)") }
            pipelines[name] = try device.makeComputePipelineState(function: function)
        }
        self.pipelines = pipelines
    }

    /// The sole renderer test seam. Encoded input is colour-managed before Metal;
    /// linear input already belongs to the Working Space. All eleven passes run.
    public func render(image: RenderImage, profile: Profile, settings: RenderSettings = .init()) throws -> RenderedPixels {
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
        let cube = try makeColourCube(profile.colourCube)
        let scratch = try decoder.makeTexture(width: input.width, height: input.height)
        guard let command = queue.makeCommandBuffer() else { throw FilmError.invalid("Cannot create render command") }
        var source = input
        var destination = scratch
        for pass in Pass.allCases {
            let name = pass == .filmResponse ? "filmResponse" : pass == .outputTransform ? "outputTransform" : "passthrough"
            guard let encoder = command.makeComputeCommandEncoder(), let pipeline = pipelines[name] else {
                throw FilmError.invalid("Cannot encode \(pass)")
            }
            encoder.label = pass.rawValue
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(source, index: 0)
            encoder.setTexture(destination, index: 1)
            encoder.setTexture(cube, index: 2)
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
