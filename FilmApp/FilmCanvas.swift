import SwiftUI
import MetalKit
import FilmEngine

struct FilmCanvas: UIViewRepresentable {
    let image: RenderedPixels
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> MTKView {
        let view = EDRMetalView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .rgba16Float
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.extendedDisplayP3)
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.delegate = context.coordinator
        return view
    }
    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.image = image
        view.setNeedsDisplay()
    }

    @MainActor final class Coordinator: NSObject, MTKViewDelegate {
        var image: RenderedPixels?
        private var pipeline: (any MTLRenderPipelineState)?
        private var queue: (any MTLCommandQueue)?
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
        func draw(in view: MTKView) {
            guard let device = view.device, let image,
                  let drawable = view.currentDrawable, let descriptor = view.currentRenderPassDescriptor else { return }
            do {
                if pipeline == nil {
                    let source = """
                    #include <metal_stdlib>
                    using namespace metal;
                    struct Vertex { float4 position [[position]]; float2 uv; };
                    vertex Vertex canvasVertex(uint id [[vertex_id]]) {
                        float2 uv = float2((id << 1) & 2, id & 2);
                        return {float4(uv * float2(2, -2) + float2(-1, 1), 0, 1), uv};
                    }
                    fragment half4 canvasFragment(Vertex v [[stage_in]], texture2d<half> image [[texture(0)]]) {
                        constexpr sampler s(filter::linear, address::clamp_to_edge);
                        half4 pixel = image.sample(s, v.uv);
                        return half4(pixel.rgb * pixel.a, pixel.a);
                    }
                    """
                    let library = try device.makeLibrary(source: source, options: nil)
                    let state = MTLRenderPipelineDescriptor()
                    state.vertexFunction = library.makeFunction(name: "canvasVertex")
                    state.fragmentFunction = library.makeFunction(name: "canvasFragment")
                    state.colorAttachments[0].pixelFormat = .rgba16Float
                    pipeline = try device.makeRenderPipelineState(descriptor: state)
                    queue = device.makeCommandQueue()
                }
                let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                    width: image.width, height: image.height, mipmapped: false)
                textureDescriptor.usage = .shaderRead
                guard let texture = device.makeTexture(descriptor: textureDescriptor),
                      let command = queue?.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: descriptor),
                      let pipeline else { return }
                image.rgba.withUnsafeBytes {
                    texture.replace(region: MTLRegionMake2D(0, 0, image.width, image.height), mipmapLevel: 0,
                                    withBytes: $0.baseAddress!, bytesPerRow: image.width * 8)
                }
                encoder.setRenderPipelineState(pipeline)
                encoder.setFragmentTexture(texture, index: 0)
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
