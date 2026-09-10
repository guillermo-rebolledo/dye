import SwiftUI
import MetalKit
import FilmEngine

struct FilmCanvas: UIViewRepresentable {
    let image: RenderedPixels
    var loupe: Loupe?

    /// Normalized image focus and finger travel, independent of view size.
    struct Loupe: Equatable {
        var focus = CGPoint(x: 0.5, y: 0.5)
        var translation = CGSize.zero

        func samplingRect(image: CGSize, drawable: CGSize) -> SIMD4<Float> {
            // One Preview texel per physical display pixel, not per UIKit point.
            let width = drawable.width / max(image.width, 1)
            let height = drawable.height / max(image.height, 1)
            let x = width >= 1 ? (1 - width) / 2 : min(max(focus.x * (1 - width) - translation.width * width, 0), 1 - width)
            let y = height >= 1 ? (1 - height) / 2 : min(max(focus.y * (1 - height) - translation.height * height, 0), 1 - height)
            // Align the crop to texels so linear sampling cannot blur pixel pitch.
            return SIMD4(Float((x * image.width).rounded() / image.width),
                         Float((y * image.height).rounded() / image.height), Float(width), Float(height))
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> MTKView {
        let view = EDRMetalView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.isOpaque = false
        view.backgroundColor = .clear
        view.colorPixelFormat = .rgba16Float
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.extendedDisplayP3)
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.delegate = context.coordinator
        return view
    }
    func updateUIView(_ view: MTKView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.image?.id != image.id || coordinator.loupe != loupe else { return }
        coordinator.image = image
        coordinator.loupe = loupe
        view.setNeedsDisplay()
    }

    @MainActor final class Coordinator: NSObject, MTKViewDelegate {
        var image: RenderedPixels?
        var loupe: Loupe?
        // All canvases use the system default device and the same pixel format.
        private static var sharedPipeline: (any MTLRenderPipelineState)?
        private var texture: (any MTLTexture)?
        private var uploadedImageID: UUID?
        private var pipeline: (any MTLRenderPipelineState)?
        private var queue: (any MTLCommandQueue)?
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { view.setNeedsDisplay() }
        func draw(in view: MTKView) {
            guard let device = view.device, let image,
                  let drawable = view.currentDrawable, let descriptor = view.currentRenderPassDescriptor else { return }
            do {
                if pipeline == nil { pipeline = Self.sharedPipeline }
                if pipeline == nil {
                    let source = """
                    #include <metal_stdlib>
                    using namespace metal;
                    struct Vertex { float4 position [[position]]; float2 uv; };
                    vertex Vertex canvasVertex(uint id [[vertex_id]]) {
                        float2 uv = float2((id << 1) & 2, id & 2);
                        return {float4(uv * float2(2, -2) + float2(-1, 1), 0, 1), uv};
                    }
                    fragment half4 canvasFragment(Vertex v [[stage_in]], texture2d<half> image [[texture(0)]],
                                                  constant float4 &crop [[buffer(0)]]) {
                        constexpr sampler s(filter::linear, address::clamp_to_edge);
                        float2 uv = crop.xy + v.uv * crop.zw;
                        if (any(uv < 0) || any(uv > 1)) return half4(0);
                        half4 pixel = image.sample(s, uv);
                        return half4(pixel.rgb * pixel.a, pixel.a);
                    }
                    """
                    let library = try device.makeLibrary(source: source, options: nil)
                    let state = MTLRenderPipelineDescriptor()
                    state.vertexFunction = library.makeFunction(name: "canvasVertex")
                    state.fragmentFunction = library.makeFunction(name: "canvasFragment")
                    state.colorAttachments[0].pixelFormat = .rgba16Float
                    pipeline = try device.makeRenderPipelineState(descriptor: state)
                    Self.sharedPipeline = pipeline
                }
                if queue == nil { queue = device.makeCommandQueue() }
                if uploadedImageID != image.id {
                    let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                        width: image.width, height: image.height, mipmapped: false)
                    textureDescriptor.usage = .shaderRead
                    guard let texture = device.makeTexture(descriptor: textureDescriptor) else { return }
                    image.rgba.withUnsafeBytes {
                        texture.replace(region: MTLRegionMake2D(0, 0, image.width, image.height), mipmapLevel: 0,
                                        withBytes: $0.baseAddress!, bytesPerRow: image.width * 8)
                    }
                    self.texture = texture
                    uploadedImageID = image.id
                }
                guard let texture, let command = queue?.makeCommandBuffer(),
                      let encoder = command.makeRenderCommandEncoder(descriptor: descriptor),
                      let pipeline else { return }
                encoder.setRenderPipelineState(pipeline)
                encoder.setFragmentTexture(texture, index: 0)
                var crop = loupe?.samplingRect(image: CGSize(width: image.width, height: image.height),
                                              drawable: view.drawableSize) ?? SIMD4<Float>(0, 0, 1, 1)
                encoder.setFragmentBytes(&crop, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                encoder.endEncoding()
                command.present(drawable)
                command.commit()
            } catch { assertionFailure("Canvas pipeline: \(error)") }
        }
    }
}

/// Re-evaluate capability when the canvas moves to another display.
private final class EDRMetalView: MTKView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        (layer as? CAMetalLayer)?.wantsExtendedDynamicRangeContent = (window?.screen.potentialEDRHeadroom ?? 1) > 1
        setNeedsDisplay()
    }
}
