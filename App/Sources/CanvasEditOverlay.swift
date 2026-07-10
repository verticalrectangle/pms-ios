//  CanvasEditOverlay.swift
//  Direct-manipulation canvas editing (CANVAS_PLAN.md) — the SwiftUI port of
//  desktop ui/canvas.cpp's selection handles: move / corner scale / edge scale /
//  rotate knob, with border+centre snapping. Geometry is pure math over the
//  engine's fraction-of-canvas transform model; every commit crosses
//  pms_command (begin_batch → set_clip_props → end_batch = one undo entry).

import SwiftUI

// MARK: - Geometry (port of canvas.cpp compute_video_bbox)

/// Maps the engine transform model onto the on-screen preview box. All rects
/// are UNROTATED view-point bboxes; rotation is applied about the bbox centre.
struct CanvasGeometry {
    let box: CGSize

    /// Unrotated bbox of a video-like clip: aspect-fit the (cropped) source
    /// into the canvas, scale, centre at pos. Unknown source size (image not
    /// probed yet) falls back to the full canvas — same as desktop before the
    /// first decoded frame.
    func videoBBox(_ c: Clip) -> CGRect {
        let w = box.width, h = box.height
        var fitW = w, fitH = h
        if let src = c.sourceSize, src.width > 0, src.height > 0 {
            let cw = src.width * (1 - c.cropL - c.cropR)
            let ch = src.height * (1 - c.cropT - c.cropB)
            let va = (cw > 0 && ch > 0) ? cw / ch : 1
            let ca = w / h
            if va > ca { fitW = w; fitH = w / CGFloat(va) }
            else       { fitH = h; fitW = h * CGFloat(va) }
        }
        let hw = fitW * CGFloat(c.scaleX) * 0.5, hh = fitH * CGFloat(c.scaleY) * 0.5
        return CGRect(x: CGFloat(c.posX) * w - hw, y: CGFloat(c.posY) * h - hh,
                      width: hw * 2, height: hh * 2)
    }

    func bbox(_ c: Clip) -> CGRect {
        c.textKind ? TextLayoutModel.bbox(for: c, in: box) : videoBBox(c)
    }

    /// Rotation-aware point-in-clip test (canvas tap hit-testing).
    func hits(_ c: Clip, point: CGPoint) -> Bool {
        let r = bbox(c)
        let u = Self.unrotate(point, about: CGPoint(x: r.midX, y: r.midY),
                              degrees: c.rotation)
        return r.insetBy(dx: -8, dy: -8).contains(u)
    }

    static func unrotate(_ p: CGPoint, about c: CGPoint, degrees: Double) -> CGPoint {
        let rad = -degrees * .pi / 180
        let dx = p.x - c.x, dy = p.y - c.y
        return CGPoint(x: c.x + dx * CGFloat(cos(rad)) - dy * CGFloat(sin(rad)),
                       y: c.y + dx * CGFloat(sin(rad)) + dy * CGFloat(cos(rad)))
    }
}

// MARK: - Text layout model

/// The single text-placement source shared by LayerFeeder.rasterText (the
/// committed engine layer), LyricOverlay (live-edit preview) and the canvas
/// bbox/handles — so what the handles frame is exactly what renders.
/// Desktop semantics (app.h:173-178): font_size is a FRACTION OF CANVAS
/// HEIGHT (0 = default); sub_pos 0 bottom / 1 centre / 2 top / 3 custom-Y;
/// sub_pos_x anchors the column horizontally; sub_wrap_w is the column width
/// as a fraction of canvas width; the block clamps into the vertical safe zone.
enum TextLayoutModel {
    /// Legacy raster parity: 0.12 × width on a 1080×1920 basis.
    static let defaultFontFrac = 0.0675
    static let safeTop = 0.08, safeBot = 0.20      // engine_seams.h SAFE_TOP/BOT

    struct Layout {
        var rect: CGRect
        var fontSize: CGFloat
        var alignment: NSTextAlignment
    }

    /// Lay a clip's text block out inside a target of `size` (points or pixels
    /// — the model is pure fractions, so both callers agree).
    static func layout(_ text: String, clip: Clip, in size: CGSize) -> Layout {
        let fsz = CGFloat(clip.fontSize > 0 ? clip.fontSize : defaultFontFrac) * size.height
        let wrapW = CGFloat(min(max(clip.subWrapW, 0.1), 1)) * size.width
        let align: NSTextAlignment = clip.subAnchorH == 0 ? .left
                                   : clip.subAnchorH == 2 ? .right : .center
        let para = NSMutableParagraphStyle()
        para.alignment = align
        let font = UIFont.systemFont(ofSize: fsz, weight: .black)
        let bounds = ((text.isEmpty ? " " : text) as NSString).boundingRect(
            with: CGSize(width: wrapW, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font, .paragraphStyle: para], context: nil)
        let bh = ceil(bounds.height)

        let ax = CGFloat(clip.subPosX) * size.width
        let x: CGFloat = clip.subAnchorH == 0 ? ax
                       : clip.subAnchorH == 2 ? ax - wrapW : ax - wrapW / 2

        var y: CGFloat
        switch clip.subPos {
        case 1:  y = (size.height - bh) / 2
        case 2:  y = CGFloat(safeTop) * size.height
        case 3:  y = CGFloat(clip.subPosY) * size.height - bh / 2
        default: y = size.height * CGFloat(1 - safeBot) - bh
        }
        // Vertical safe-zone clamp (text_renderer.cpp:147-150)
        y = min(max(y, CGFloat(safeTop) * size.height),
                size.height * CGFloat(1 - safeBot) - bh)

        return Layout(rect: CGRect(x: x, y: y, width: wrapW, height: bh),
                      fontSize: fsz, alignment: align)
    }

    static func bbox(for c: Clip, in box: CGSize) -> CGRect {
        layout(c.label, clip: c, in: box).rect
    }
}

// MARK: - Selection / hit-test model hooks

extension EditorModel {
    /// The clip whose transform handles show. Desktop parity
    /// (canvas.cpp draw_canvas_handles): selecting a coupled glass FX brick
    /// hands the handles to its host content clip underneath, so move/scale/
    /// rotate works no matter which layer of the stack is selected.
    var canvasTargetClip: Clip? {
        guard let r = selectedRef else { return nil }
        let track = tracks[r.track]
        if r.kind == .clip {
            guard track.kind == .video || track.kind == .lyric else { return nil }
            return track.clips[r.index]
        }
        let b = track.bricks[r.index]
        guard b.coupled, track.kind == .video else { return nil }
        return track.clips.first { $0.start < b.end && b.start < $0.end }
    }

    /// Tap on the canvas at `point` (view points inside `box`): select the
    /// top-most active clip under it; tapping the same spot again cycles one
    /// layer deeper (the touch stand-in for desktop Alt+click layer cycling).
    /// Returns false when no layer was hit.
    func canvasSelect(at point: CGPoint, box: CGSize) -> Bool {
        guard cropEditID == nil else { return true }   // crop mode owns the canvas
        let geo = CanvasGeometry(box: box)
        var hitIDs: [String] = []
        for tr in tracks where tr.kind == .video || tr.kind == .lyric {
            for c in tr.clips where c.start <= playhead && playhead < c.end {
                if geo.hits(c, point: point) { hitIDs.append(c.id) }
            }
        }
        guard !hitIDs.isEmpty else { return false }
        if let cur = selectedID, let i = hitIDs.firstIndex(of: cur) {
            selectedID = hitIDs[(i + 1) % hitIDs.count]
        } else {
            selectedID = hitIDs[0]
        }
        return true
    }
}

// MARK: - Overlay

/// The editing surface layered over MetalPreview, laid out against the same
/// computed `box` (the MTKView is frame-sized; flex geometry would drift).
struct CanvasEditOverlay: View {
    @ObservedObject var model: EditorModel
    let box: CGSize

    var body: some View {
        ZStack {
            SafeZoneOverlay(mode: model.safeZones, box: box)
            if let cropClip = model.cropEditClip, !model.exporting {
                CropBox(model: model, clip: cropClip, geo: CanvasGeometry(box: box))
            } else if let clip = model.canvasTargetClip, clip.address != nil,
                      !model.exporting {
                HandleBox(model: model, clip: clip, geo: CanvasGeometry(box: box))
            }
        }
        .frame(width: box.width, height: box.height)
        .coordinateSpace(name: "pmsCanvas")
    }
}

/// Which handle a drag started on (desktop CanvasHandle).
private enum Handle {
    case body
    case cornerTL, cornerTR, cornerBL, cornerBR
    case edgeL, edgeR, edgeT, edgeB
    case rotate
}

/// Selection box + handles + rotate knob, plus the drag state machine.
/// All drag math runs in the UNROTATED canvas space ("pmsCanvas") and is
/// projected into the clip's local frame with the start-of-gesture rotation.
private struct HandleBox: View {
    @ObservedObject var model: EditorModel
    let clip: Clip
    let geo: CanvasGeometry

    private static let knobDist: CGFloat = 28      // desktop ROT_DIST
    private static let cornerSize: CGFloat = 11
    private static let snapTol: CGFloat = 6
    private static let rotSnapDeg: Double = 5      // catch radius around 45° stops

    /// Start-of-gesture snapshot (desktop CanvasTransform).
    private struct DragCtx {
        var handle: Handle
        var startLoc: CGPoint
        var center: CGPoint
        var halfW: CGFloat, halfH: CGFloat
        var posX: Double, posY: Double
        var scaleX: Double, scaleY: Double
        var rotation: Double
        var fontFrac: Double        // text: resolved font_size fraction at start
        var wrapW: Double           // text: sub_wrap_w at start
    }
    @State private var ctx: DragCtx?
    @State private var snapX: CGFloat?    // active alignment guides (view pts)
    @State private var snapY: CGFloat?

    var body: some View {
        let r = geo.bbox(clip)
        let ctr = CGPoint(x: r.midX, y: r.midY)
        ZStack {
            selectionBox(r)
                .rotationEffect(.degrees(clip.rotation))
                .position(ctr)
            guides
        }
    }

    // MARK: drawing

    private func selectionBox(_ r: CGRect) -> some View {
        ZStack {
            // Body: outline + interior drag surface
            Rectangle()
                .fill(Color.white.opacity(0.001))   // hit-testable interior
                .overlay(Rectangle().strokeBorder(.white.opacity(0.75), lineWidth: 1))
                .frame(width: r.width, height: r.height)
                .gesture(drag(.body))

            // Rotate stem + knob (desktop: floats ROT_DIST above the top edge,
            // rotating with the clip). Text rotates raster-side — no knob (§4 gap).
            if !clip.textKind {
                Rectangle().fill(.white.opacity(0.6))
                    .frame(width: 1, height: Self.knobDist)
                    .offset(y: -r.height / 2 - Self.knobDist / 2)
                    .allowsHitTesting(false)
                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(.black.opacity(0.7), lineWidth: 1))
                    .overlay(Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                        .font(.system(size: 7, weight: .bold)).foregroundStyle(.black.opacity(0.75)))
                    .frame(width: 16, height: 16)
                    .contentShape(Circle().inset(by: -8))
                    .offset(y: -r.height / 2 - Self.knobDist)
                    .gesture(drag(.rotate))
            }

            // Edge handles: single-axis scale; on text the L/R pair drags the
            // wrap column width (desktop EdgeL/R → sub_wrap_w) and T/B is gone.
            edgeHandle(w: 4, h: 18).offset(x: -r.width / 2).gesture(drag(.edgeL))
            edgeHandle(w: 4, h: 18).offset(x: r.width / 2).gesture(drag(.edgeR))
            if !clip.textKind {
                edgeHandle(w: 18, h: 4).offset(y: -r.height / 2).gesture(drag(.edgeT))
                edgeHandle(w: 18, h: 4).offset(y: r.height / 2).gesture(drag(.edgeB))
            }

            // Corner handles (uniform scale)
            cornerHandle.offset(x: -r.width / 2, y: -r.height / 2).gesture(drag(.cornerTL))
            cornerHandle.offset(x: r.width / 2, y: -r.height / 2).gesture(drag(.cornerTR))
            cornerHandle.offset(x: -r.width / 2, y: r.height / 2).gesture(drag(.cornerBL))
            cornerHandle.offset(x: r.width / 2, y: r.height / 2).gesture(drag(.cornerBR))
        }
        .frame(width: r.width, height: r.height)
    }

    private var cornerHandle: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(.white)
            .overlay(RoundedRectangle(cornerRadius: 2.5).strokeBorder(.black.opacity(0.7), lineWidth: 0.8))
            .frame(width: Self.cornerSize, height: Self.cornerSize)
            .contentShape(Rectangle().inset(by: -9))
    }

    private func edgeHandle(w: CGFloat, h: CGFloat) -> some View {
        Capsule()
            .fill(.white)
            .overlay(Capsule().strokeBorder(.black.opacity(0.7), lineWidth: 0.8))
            .frame(width: w, height: h)
            .contentShape(Rectangle().inset(by: -9))
    }

    /// Alignment guides while a body drag is snapped (desktop snap_move).
    private var guides: some View {
        ZStack {
            if let x = snapX {
                Rectangle().fill(Theme.accent.opacity(0.8))
                    .frame(width: 1, height: geo.box.height)
                    .position(x: x, y: geo.box.height / 2)
            }
            if let y = snapY {
                Rectangle().fill(Theme.accent.opacity(0.8))
                    .frame(width: geo.box.width, height: 1)
                    .position(x: geo.box.width / 2, y: y)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: drag state machine

    private func drag(_ handle: Handle) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("pmsCanvas"))
            .onChanged { v in
                if ctx == nil { begin(handle, at: v.startLocation) }
                update(v.location)
            }
            .onEnded { _ in end() }
    }

    private func begin(_ handle: Handle, at p: CGPoint) {
        let r = geo.bbox(clip)
        ctx = DragCtx(handle: handle, startLoc: p,
                      center: CGPoint(x: r.midX, y: r.midY),
                      halfW: r.width / 2, halfH: r.height / 2,
                      posX: clip.posX, posY: clip.posY,
                      scaleX: clip.scaleX, scaleY: clip.scaleY,
                      rotation: clip.rotation,
                      fontFrac: clip.fontSize > 0 ? clip.fontSize : TextLayoutModel.defaultFontFrac,
                      wrapW: clip.subWrapW)
        model.beginCanvasGesture()
    }

    private func update(_ p: CGPoint) {
        guard let c = ctx, let id = clipID else { return }
        switch c.handle {
        case .body:
            var cx = c.center.x + (p.x - c.startLoc.x)
            var cy = c.center.y + (p.y - c.startLoc.y)
            // Snap the centre to canvas borders + centre; the social safe-box
            // edges join the target set while its overlay is on (desktop snap_move).
            snapX = nil; snapY = nil
            var xTargets: [CGFloat] = [0, geo.box.width / 2, geo.box.width]
            var yTargets: [CGFloat] = [0, geo.box.height / 2, geo.box.height]
            if model.safeZones == .social {
                xTargets += [0.08 * geo.box.width, (1 - 0.12) * geo.box.width]
                yTargets += [0.10 * geo.box.height, (1 - 0.22) * geo.box.height]
            }
            for gx in xTargets where abs(cx - gx) <= Self.snapTol {
                cx = gx; snapX = gx; break
            }
            for gy in yTargets where abs(cy - gy) <= Self.snapTol {
                cy = gy; snapY = gy; break
            }
            if clip.textKind {
                // Text moves through the sub_* placement model (desktop body
                // drag): custom-Y + centre anchor at the dragged block centre.
                model.updateCanvasGesture(id, ["sub_pos": 3, "sub_anchor_h": 1,
                                               "sub_pos_x": Double(cx / geo.box.width),
                                               "sub_pos_y": Double(cy / geo.box.height)])
            } else {
                model.updateCanvasGesture(id, ["pos_x": Double(cx / geo.box.width),
                                               "pos_y": Double(cy / geo.box.height)])
            }

        case .rotate:
            let a0 = atan2(c.startLoc.y - c.center.y, c.startLoc.x - c.center.x)
            let a1 = atan2(p.y - c.center.y, p.x - c.center.x)
            var deg = c.rotation + Double(a1 - a0) * 180 / .pi
            // 45°-stop snapping (desktop s_rot_snapped)
            let stop = (deg / 45).rounded() * 45
            if abs(deg - stop) <= Self.rotSnapDeg { deg = stop }
            deg = deg.truncatingRemainder(dividingBy: 360)
            model.updateCanvasGesture(id, ["rotation": deg])

        case .cornerTL, .cornerTR, .cornerBL, .cornerBR:
            // Uniform scale: ratio of finger→centre distances (rotation-proof).
            // On text the corners scale font_size (desktop corner drag).
            let d0 = max(8, hypot(c.startLoc.x - c.center.x, c.startLoc.y - c.center.y))
            let d1 = hypot(p.x - c.center.x, p.y - c.center.y)
            let f = Double(max(0.05, d1 / d0))
            if clip.textKind {
                model.updateCanvasGesture(id, ["font_size": min(max(c.fontFrac * f, 0.01), 0.5)])
            } else {
                model.updateCanvasGesture(id, ["scale_x": c.scaleX * f,
                                               "scale_y": c.scaleY * f])
            }

        case .edgeL, .edgeR:
            // Single-axis: project the finger into the clip's local X.
            // On text this drags the wrap column width (desktop → sub_wrap_w).
            let l0 = CanvasGeometry.unrotate(c.startLoc, about: c.center, degrees: c.rotation)
            let l1 = CanvasGeometry.unrotate(p, about: c.center, degrees: c.rotation)
            let x0 = max(8, abs(l0.x - c.center.x))
            let f = Double(max(0.05, abs(l1.x - c.center.x) / x0))
            if clip.textKind {
                model.updateCanvasGesture(id, ["sub_wrap_w": min(max(c.wrapW * f, 0.1), 1)])
            } else {
                model.updateCanvasGesture(id, ["scale_x": c.scaleX * f])
            }

        case .edgeT, .edgeB:
            let l0 = CanvasGeometry.unrotate(c.startLoc, about: c.center, degrees: c.rotation)
            let l1 = CanvasGeometry.unrotate(p, about: c.center, degrees: c.rotation)
            let y0 = max(8, abs(l0.y - c.center.y))
            let f = Double(max(0.05, abs(l1.y - c.center.y) / y0))
            model.updateCanvasGesture(id, ["scale_y": c.scaleY * f])
        }
    }

    private func end() {
        ctx = nil
        snapX = nil; snapY = nil
        model.endCanvasGesture()
    }

    private var clipID: String? { model.canvasTargetClip?.id }
}

// MARK: - Safe zones (stage 6)

/// Standard title-safe box (engine_seams.h SAFE_*) or the social-app envelope
/// (canvas.cpp SOCIAL_*: tabs / caption / rail / gutter) — view-only chrome.
private struct SafeZoneOverlay: View {
    let mode: EditorModel.SafeZoneMode
    let box: CGSize

    var body: some View {
        ZStack {
            switch mode {
            case .off:
                EmptyView()
            case .standard:
                let r = CGRect(x: 0.05 * box.width, y: 0.08 * box.height,
                               width: 0.90 * box.width,
                               height: (1 - 0.08 - 0.20) * box.height)
                dashedRect(r)
            case .social:
                // Dim the bands social chrome covers; outline what survives.
                Group {
                    Color.black.opacity(0.30)
                        .frame(width: box.width, height: 0.10 * box.height)
                        .position(x: box.width / 2, y: 0.05 * box.height)
                    Color.black.opacity(0.30)
                        .frame(width: box.width, height: 0.22 * box.height)
                        .position(x: box.width / 2, y: (1 - 0.11) * box.height)
                    Color.black.opacity(0.30)
                        .frame(width: 0.12 * box.width, height: 0.68 * box.height)
                        .position(x: (1 - 0.06) * box.width, y: 0.44 * box.height)
                    Color.black.opacity(0.30)
                        .frame(width: 0.08 * box.width, height: 0.68 * box.height)
                        .position(x: 0.04 * box.width, y: 0.44 * box.height)
                }
                let r = CGRect(x: 0.08 * box.width, y: 0.10 * box.height,
                               width: (1 - 0.08 - 0.12) * box.width,
                               height: (1 - 0.10 - 0.22) * box.height)
                dashedRect(r)
            }
        }
        .allowsHitTesting(false)
    }

    private func dashedRect(_ r: CGRect) -> some View {
        Rectangle()
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            .foregroundStyle(.white.opacity(0.5))
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
    }
}

// MARK: - Crop-edit mode (CANVAS_PLAN.md stage 4)

/// Crop window over the live render. Desktop shows the clip's FULL frame while
/// cropping (app-side render); the iOS engine renders the crop live, so the
/// full-frame rect is RECONSTRUCTED from the current bbox + crop values and
/// frozen per drag — handle→fraction mapping stays linear (explicit v1
/// deviation, CANVAS_PLAN.md §4).
private struct CropBox: View {
    @ObservedObject var model: EditorModel
    let clip: Clip
    let geo: CanvasGeometry

    /// 0 none, 1 TL, 2 TR, 3 BR, 4 BL, 5 T, 6 B, 7 L, 8 R, 9 body (desktop s_crop.drag)
    private struct DragCtx {
        var handle: Int
        var startLoc: CGPoint
        var frame: CGRect                  // reconstructed full source frame (canvas pts, unrotated)
        var center: CGPoint                // rotation pivot (bbox centre at start)
        var rotation: Double
        var l: Double, t: Double, r: Double, b: Double
    }
    @State private var ctx: DragCtx?

    var body: some View {
        let r = geo.videoBBox(clip)
        let ctr = CGPoint(x: r.midX, y: r.midY)
        ZStack {
            // Dimmed surround with a clear hole at the crop window
            ZStack {
                Color.black.opacity(0.45)
                Rectangle()
                    .frame(width: r.width, height: r.height)
                    .rotationEffect(.degrees(clip.rotation))
                    .position(ctr)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .allowsHitTesting(false)

            // Window outline + handles (rotate with the clip)
            window(r)
                .rotationEffect(.degrees(clip.rotation))
                .position(ctr)

            pill
        }
    }

    private func window(_ r: CGRect) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .overlay(Rectangle().strokeBorder(.white, lineWidth: 1.2))
                .frame(width: r.width, height: r.height)
                .gesture(drag(9))
            // thirds grid
            ForEach(1..<3) { i in
                Rectangle().fill(.white.opacity(0.25)).frame(width: 0.7, height: r.height)
                    .offset(x: r.width * (CGFloat(i) / 3 - 0.5))
                Rectangle().fill(.white.opacity(0.25)).frame(width: r.width, height: 0.7)
                    .offset(y: r.height * (CGFloat(i) / 3 - 0.5))
            }
            cropHandle.offset(x: -r.width / 2, y: -r.height / 2).gesture(drag(1))
            cropHandle.offset(x: r.width / 2, y: -r.height / 2).gesture(drag(2))
            cropHandle.offset(x: r.width / 2, y: r.height / 2).gesture(drag(3))
            cropHandle.offset(x: -r.width / 2, y: r.height / 2).gesture(drag(4))
            cropHandle.offset(y: -r.height / 2).gesture(drag(5))
            cropHandle.offset(y: r.height / 2).gesture(drag(6))
            cropHandle.offset(x: -r.width / 2).gesture(drag(7))
            cropHandle.offset(x: r.width / 2).gesture(drag(8))
        }
        .frame(width: r.width, height: r.height)
    }

    private var cropHandle: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(.white)
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(.black.opacity(0.7), lineWidth: 0.8))
            .frame(width: 12, height: 12)
            .contentShape(Rectangle().inset(by: -10))
    }

    /// Aspect presets + Reset / Cancel / Apply (desktop crop pill).
    private var pill: some View {
        HStack(spacing: 10) {
            ForEach(Array(zip(["Free", "1:1", "9:16", "16:9"], [0.0, 1.0, 9.0 / 16, 16.0 / 9]).enumerated()),
                    id: \.offset) { _, item in
                Button(item.0) { if item.1 > 0 { applyAspect(item.1) } }
                    .font(.label(10)).tint(Theme.txtBody)
            }
            Divider().frame(height: 14)
            Button("Reset") { setCrop(0, 0, 0, 0) }.font(.label(10)).tint(Theme.txtBody)
            Button("Cancel") { model.cancelCrop() }.font(.label(10)).tint(Theme.txtMuted)
            Button("Apply") { model.applyCrop() }.font(.label(10)).tint(Theme.accent)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .glass(12, flat: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 8)
    }

    // MARK: crop math

    private func drag(_ handle: Int) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("pmsCanvas"))
            .onChanged { v in
                if ctx == nil { begin(handle, at: v.startLocation) }
                update(v.location)
            }
            .onEnded { _ in
                ctx = nil
                model.flushCanvasGesture()
            }
    }

    private func begin(_ handle: Int, at p: CGPoint) {
        let r = geo.videoBBox(clip)
        // Reconstruct the full source frame: the bbox covers (1-l-r) × (1-t-b)
        // of it, offset by the leading crop fractions.
        let wf = max(0.05, 1 - clip.cropL - clip.cropR)
        let hf = max(0.05, 1 - clip.cropT - clip.cropB)
        let fw = r.width / CGFloat(wf), fh = r.height / CGFloat(hf)
        let frame = CGRect(x: r.minX - CGFloat(clip.cropL) * fw,
                           y: r.minY - CGFloat(clip.cropT) * fh,
                           width: fw, height: fh)
        ctx = DragCtx(handle: handle, startLoc: p, frame: frame,
                      center: CGPoint(x: r.midX, y: r.midY),
                      rotation: clip.rotation,
                      l: clip.cropL, t: clip.cropT, r: clip.cropR, b: clip.cropB)
    }

    private func update(_ p: CGPoint) {
        guard let c = ctx else { return }
        // Drag delta in the clip's local (unrotated) frame
        let l0 = CanvasGeometry.unrotate(c.startLoc, about: c.center, degrees: c.rotation)
        let l1 = CanvasGeometry.unrotate(p, about: c.center, degrees: c.rotation)
        let dx = Double((l1.x - l0.x) / c.frame.width)
        let dy = Double((l1.y - l0.y) / c.frame.height)

        var l = c.l, t = c.t, r = c.r, b = c.b
        switch c.handle {
        case 1: l = c.l + dx; t = c.t + dy            // TL
        case 2: r = c.r - dx; t = c.t + dy            // TR
        case 3: r = c.r - dx; b = c.b - dy            // BR
        case 4: l = c.l + dx; b = c.b - dy            // BL
        case 5: t = c.t + dy                          // T
        case 6: b = c.b - dy                          // B
        case 7: l = c.l + dx                          // L
        case 8: r = c.r - dx                          // R
        case 9:                                       // body: pan the window
            let w = 1 - c.l - c.r, h = 1 - c.t - c.b
            l = min(max(0, c.l + dx), 1 - w); r = 1 - w - l
            t = min(max(0, c.t + dy), 1 - h); b = 1 - h - t
        default: break
        }
        // Engine clamp: each side ≤ 0.95 − opposite
        l = max(0, min(l, 0.95 - r)); r = max(0, min(r, 0.95 - l))
        t = max(0, min(t, 0.95 - b)); b = max(0, min(b, 0.95 - t))
        setCrop(l, t, r, b)
    }

    /// Preset: largest window with display aspect `a`, centred on the current one.
    private func applyAspect(_ a: Double) {
        guard let src = clip.sourceSize, src.width > 0, src.height > 0 else { return }
        let s = Double(src.width / src.height)
        let wf = 1 - clip.cropL - clip.cropR
        let hf = 1 - clip.cropT - clip.cropB
        var nwf = wf, nhf = hf
        if wf * s / hf > a { nwf = hf * a / s }       // too wide → narrow it
        else               { nhf = wf * s / a }       // too tall → shorten it
        let cx = clip.cropL + wf / 2, cy = clip.cropT + hf / 2
        let l = min(max(0, cx - nwf / 2), 1 - nwf)
        let t = min(max(0, cy - nhf / 2), 1 - nhf)
        setCrop(l, t, 1 - nwf - l, 1 - nhf - t)
    }

    private func setCrop(_ l: Double, _ t: Double, _ r: Double, _ b: Double) {
        model.updateCanvasGesture(clip.id, ["crop_l": l, "crop_t": t,
                                            "crop_r": r, "crop_b": b])
    }
}
