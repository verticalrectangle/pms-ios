//  MetalPreview.swift
//  The canvas. The engine composites the current frame into a Metal texture via
//  pms_render; here we host an MTKView and, each draw, hand the drawable's texture
//  to EngineStore.render(into:). No pixels are drawn on the Swift side — the C++
//  GL/Metal pipeline owns the image, exactly as it does at export (pixel-identical).

import SwiftUI
import MetalKit

struct MetalPreview: UIViewRepresentable {
    @ObservedObject var store: EngineStore
    var paused: Bool = false   // freeze on last drawable (e.g. while fullscreen owns the live view)

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: store.device)
        view.delegate = context.coordinator
        view.framebufferOnly = false                 // engine writes into the texture
        view.colorPixelFormat = .bgra8Unorm
        view.isPaused = paused
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.layer.isOpaque = true
        // Render at the display's native pixel density — the drawable is
        // bounds × scale, so the canvas is crisp (retina), not point-resolution.
        view.autoResizeDrawable = true
        view.contentScaleFactor = view.window?.screen.scale ?? UIScreen.main.scale
        view.layer.contentsScale = view.contentScaleFactor
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.store = store
        view.isPaused = paused   // freeze/resume when fullscreen toggles
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        var store: EngineStore
        init(store: EngineStore) { self.store = store }
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable else { return }
            store.render(into: drawable.texture)
            drawable.present()
        }
    }
}

/// Thin overlay chrome the engine does NOT draw: filename tag + active-brick badges.
struct CanvasChrome: View {
    let clipLabel: String
    let activeBricks: [Brick]

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)
            if !clipLabel.isEmpty {
                HStack {
                    Text("\(clipLabel).MP4")
                        .font(.label(9))
                        .foregroundStyle(Theme.txtLabel)
                    Spacer()
                }
                .padding(10)
            }

            VStack(alignment: .trailing, spacing: 4) {
                ForEach(activeBricks.prefix(3)) { b in
                    let cyan = b.kind == .glassFX || b.kind == .multiFX
                    let violet = b.kind == .bodyFX
                    let c = violet ? Theme.bodyViolet : cyan ? Theme.glassCyan : Theme.accent
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1).fill(c).frame(width: 5, height: 5)
                        Text(b.title.uppercased())
                            .font(.label(8)).tracking(0.6).foregroundStyle(c)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(c.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(c.opacity(0.7), lineWidth: 1))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(10)
        }
    }
}

/// Time-windowed text/title overlay on the canvas (preview). The same clips
/// will bake into export via a CATextLayer once the animation-tool path lands.
struct LyricOverlay: View {
    let clips: [Clip]
    let width: CGFloat
    var body: some View {
        VStack(spacing: width * 0.02) {
            ForEach(clips) { c in
                Text(c.label)
                    .font(.system(size: width * 0.12, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.55), radius: width * 0.02)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.4)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, width * 0.06)
        .allowsHitTesting(false)
    }
}
