// RenderView.swift — the engine's canvas: a CAMetalLayer the engine
// composites into every display-link frame. SwiftUI overlays (handles,
// pills, gizmos) live ABOVE this view in the hierarchy; the engine draws
// pixels, SwiftUI draws chrome. Butter check: drawableSize tracks the
// layer's native scale so we never upscale a small render.
import SwiftUI
import MetalKit

struct RenderView: UIViewRepresentable {
    @EnvironmentObject var engine: EngineStore

    func makeUIView(context: Context) -> MTKView {
        let v = MTKView(frame: .zero, device: engine.device)
        v.framebufferOnly = false            // engine writes via compute/blit
        v.colorPixelFormat = .bgra8Unorm
        v.preferredFramesPerSecond = 60
        v.delegate = context.coordinator
        return v
    }

    func updateUIView(_ view: MTKView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(engine: engine) }

    final class Coordinator: NSObject, MTKViewDelegate {
        let engine: EngineStore
        init(engine: EngineStore) { self.engine = engine }
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable else { return }
            engine.render(into: drawable.texture)
            drawable.present()
        }
    }
}
