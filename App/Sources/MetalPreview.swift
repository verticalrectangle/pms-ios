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

/// Live-edit text overlay on the canvas: ONLY the clip currently being typed
/// into draws here (committed titles composite engine-side). Placement comes
/// from TextLayoutModel so typing shows exactly where the raster will land.
struct LyricOverlay: View {
    let clips: [Clip]
    let box: CGSize
    var body: some View {
        SwiftUI.TimelineView(.animation) { timeline in
            ZStack {
                ForEach(clips) { c in
                    let lay = TextLayoutModel.layout(c.label.isEmpty ? " " : c.label,
                                                     clip: c, in: box)
                    let baseText = Text(c.label)
                        .font(.system(size: lay.fontSize, weight: .black))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: box.width * 0.02)
                        .multilineTextAlignment(c.subAnchorH == 0 ? .leading :
                                                c.subAnchorH == 2 ? .trailing : .center)
                        .frame(width: lay.rect.width,
                               alignment: c.subAnchorH == 0 ? .leading :
                                          c.subAnchorH == 2 ? .trailing : .center)
                        .position(x: lay.rect.midX, y: lay.rect.midY)
                    if c.clipStyle == "scratch" {
                        baseText.overlay {
                            Canvas { ctx, size in
                                let frame = Int(timeline.date.timeIntervalSinceReferenceDate * 24)
                                for i in 0..<14 {
                                    let sx = CGFloat(Self.hash01(i, frame)) * size.width
                                    let sy = CGFloat(Self.hash01(i + 7, frame)) * size.height
                                    let ang = (CGFloat(Self.hash01(i + 13, frame)) - 0.5) * .pi * 0.3
                                    let len = size.width * (0.2 + CGFloat(Self.hash01(i + 19, frame)) * 0.6)
                                    var p = Path()
                                    p.move(to: CGPoint(x: sx, y: sy))
                                    p.addLine(to: CGPoint(x: sx + cos(ang) * len,
                                                          y: sy + sin(ang) * len))
                                    ctx.stroke(p, with: .color(.black.opacity(0.7)), lineWidth: 1.5)
                                }
                            }
                        }
                    } else if c.clipStyle == "scratch-raw" {
                        // Preview approximation: the Scratchy font provides the
                        // distressed look. The actual scratch-line rendering is
                        // in the engine layer (rasterScratchRawText). Here we
                        // approximate the per-letter staggered pop by showing
                        // each letter as it arrives.
                        let frame = Int(timeline.date.timeIntervalSinceReferenceDate * 24)
                        let localT = Double(frame) / 24.0
                        let stagger = 0.06
                        HStack(spacing: 0) {
                            ForEach(Array(c.label.enumerated()), id: \.offset) { idx, ch in
                                let et = localT - Double(idx) * stagger
                                let a = et < 0 ? 0.0 : 1.0
                                Text(String(ch))
                                    .font(DisplayFonts.swiftUIFont(c.subFont, size: lay.fontSize))
                                    .foregroundColor(.white)
                                    .opacity(a)
                            }
                        }
                        .frame(width: lay.rect.width, height: lay.rect.height,
                               alignment: c.subAnchorH == 0 ? .leading :
                                          c.subAnchorH == 2 ? .trailing : .center)
                        .position(x: lay.rect.midX, y: lay.rect.midY)
                    } else {
                        baseText
                    }
                }
            }
            .frame(width: box.width, height: box.height)
            .allowsHitTesting(false)
        }
    }
    private static func hash01(_ i: Int, _ salt: Int) -> Float {
        var x = (UInt32(truncatingIfNeeded: i) &* 2654435761) ^ (UInt32(truncatingIfNeeded: salt) &* 40503)
        x ^= x >> 13; x &*= 0x5bd1e995; x ^= x >> 15
        return Float(x & 0xFFFFFF) / Float(0x1000000)
    }
}
