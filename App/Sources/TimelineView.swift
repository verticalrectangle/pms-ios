//  TimelineView.swift
//  Horizontal multi-track timeline. Content clips + the four brick flavours, a
//  ruler with second ticks + a beat grid (from analyze_audio bpm) + chapter
//  markers, and a centred playhead. Tap to seek; auto-follows during playback.

import SwiftUI

private let PPS: CGFloat = 46          // pixels per second

struct TimelineView: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var engine: EngineStore
    @State private var dragStartT: Double?

    private var t: Double { model.playhead }
    private var contentWidth: CGFloat { CGFloat(model.duration) * PPS }

    var body: some View {
        GeometryReader { geo in
            let sidePad = geo.size.width / 2
            // The content is offset so the point at time `t` sits under the
            // centred playhead; as `t` advances during playback the content
            // slides left and the playhead visibly tracks it. (.offset is a
            // cheap render transform — no per-frame relayout.)
            VStack(alignment: .leading, spacing: 3) {
                RulerView(model: model)
                ForEach(model.tracks) { track in
                    TrackLane(track: track, model: model)
                }
            }
            .frame(width: contentWidth, alignment: .topLeading)
            .offset(x: sidePad - CGFloat(t) * PPS)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
            .overlay(alignment: .center) { Playhead(model: model, engine: engine) }
            // Normal priority (NOT high) so the trim handles' high-priority drag
            // wins when you grab an edge; scrub only claims drags on empty timeline.
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { g in
                        if dragStartT == nil { dragStartT = t; model.pauseForScrub() }
                        model.seek((dragStartT ?? t) - Double(g.translation.width / PPS))
                    }
                    .onEnded { _ in dragStartT = nil }
            )
            .onTapGesture { loc in model.seek(t + Double((loc.x - sidePad) / PPS)) }
        }
    }
}

// MARK: - Ruler (seconds + beat grid + chapters)

private struct RulerView: View {
    @ObservedObject var model: EditorModel
    private var secs: Int { Int(model.duration.rounded(.up)) }
    private var beatSec: Double { 60.0 / model.bpm }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // beat grid
            if model.beatsVisible {
                ForEach(0..<Int(model.duration / beatSec), id: \.self) { i in
                    Rectangle().fill(Theme.accentA(0.12)).frame(width: 1)
                        .offset(x: CGFloat(Double(i) * beatSec) * PPS)
                }
            }
            // second ticks + timecode on the BOTTOM row (kept clear of chapters)
            ForEach(0...secs, id: \.self) { s in
                let major = s % 5 == 0
                Rectangle().fill(major ? Theme.lineStrong : Theme.lineFaint).frame(width: 1, height: 8)
                    .offset(x: CGFloat(s) * PPS, y: 18)
                if major {
                    Text(fullTC(Double(s))).font(.num(9)).foregroundStyle(Theme.txtMuted)
                        .fixedSize()
                        .offset(x: CGFloat(s) * PPS + 3, y: 16)
                }
            }
            // chapter markers on the TOP row
            ForEach(model.chapters) { m in
                VStack(spacing: 1) {
                    Text(m.label).font(.label(7)).tracking(0.6).foregroundStyle(m.color)
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 2).fill(m.color.opacity(0.16)))
                    Rectangle().fill(m.color.opacity(0.5)).frame(width: 1, height: 8)
                }
                .fixedSize()
                .offset(x: CGFloat(m.time) * PPS, y: 0)
            }
        }
        .frame(height: 34, alignment: .topLeading)
    }
}

// MARK: - Track lane

private struct TrackLane: View {
    let track: Track
    @ObservedObject var model: EditorModel
    @State private var dragID: String?     // clip picked up for reorder
    @State private var dragDX: CGFloat = 0

    private var laneHeight: CGFloat {
        switch track.kind { case .fxRail: 30; case .video: 52; case .lyric: 40; case .audio: 34 }
    }

    /// Insertion slot (index among the OTHER clips) for a clip dragged by `dx`.
    private func reorderTarget(_ dragged: Clip, dx: CGFloat) -> Int {
        let center = CGFloat(dragged.start + dragged.duration / 2) * PPS + dx
        return track.clips
            .filter { $0.id != dragged.id }
            .filter { CGFloat($0.start + $0.duration / 2) * PPS < center }
            .count
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if track.kind == .fxRail && track.bricks.isEmpty {
                Text("drop a brick here = global ▾")
                    .font(.label(8)).foregroundStyle(Theme.txtGhost).offset(x: 6, y: laneHeight/2 - 6)
            }
            ForEach(track.clips) { clip in
                let dragging = dragID == clip.id
                ContentClipView(clip: clip, kind: track.kind, selected: model.selectedID == clip.id, height: laneHeight)
                    .frame(width: CGFloat(clip.duration) * PPS)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.selectedID = (model.selectedID == clip.id) ? nil : clip.id
                    }
                    .overlay {
                        if model.selectedID == clip.id && track.kind == .video {
                            TrimHandles(clip: clip, model: model, height: laneHeight)
                        }
                    }
                    .scaleEffect(dragging ? 1.06 : 1, anchor: .center)
                    .shadow(color: dragging ? Theme.accentA(0.55) : .clear, radius: 12)
                    .offset(x: CGFloat(clip.start) * PPS + (dragging ? dragDX : 0))
                    .zIndex(dragging ? 2 : (model.selectedID == clip.id ? 1 : 0))
                    .gesture(
                        // Long-press to pick up, THEN drag to reorder. A quick drag
                        // falls through to the scrub; a tap still selects.
                        LongPressGesture(minimumDuration: 0.28)
                            .sequenced(before: DragGesture(coordinateSpace: .global))
                            .onChanged { value in
                                guard track.kind == .video, case .second(true, let drag?) = value else { return }
                                if dragID != clip.id { dragID = clip.id }
                                dragDX = drag.translation.width
                            }
                            .onEnded { _ in
                                // Use the tracked dragDX — the sequenced gesture's
                                // end value drops the drag payload (comes back nil).
                                if track.kind == .video, dragID == clip.id {
                                    model.moveClip(clip.id, toIndex: reorderTarget(clip, dx: dragDX))
                                }
                                dragID = nil; dragDX = 0
                            }
                    )
            }
            ForEach(track.bricks) { brick in
                BrickView(brick: brick, laneHeight: laneHeight,
                          selected: model.selectedID == brick.id)
                    .frame(width: CGFloat(brick.duration) * PPS)
                    .contentShape(Rectangle())
                    .onTapGesture { model.selectedID = brick.id }
                    .offset(x: CGFloat(brick.start) * PPS)
            }
        }
        // Full content width so every offset clip is inside the lane's
        // hit-testable frame (otherwise the topmost clip swallows the tap).
        .frame(maxWidth: .infinity, minHeight: laneHeight, maxHeight: laneHeight, alignment: .topLeading)
        .sensoryFeedback(.impact(weight: .medium), trigger: dragID)   // pick-up / drop
    }
}

private struct ContentClipView: View {
    let clip: Clip; let kind: TrackKind; let selected: Bool; let height: CGFloat

    private var accent: Color {
        switch kind { case .lyric: Theme.accentA(0.85); case .audio: Theme.line; default: Color.white.opacity(0.5) }
    }

    var body: some View {
        ZStack(alignment: kind == .video ? .bottomLeading : .leading) {
            RoundedRectangle(cornerRadius: 7).fill(.ultraThinMaterial)
            if kind == .video {
                if clip.thumbs.isEmpty {
                    AsyncImage(url: URL(string: "https://picsum.photos/seed/\(clip.seed)cl/240/120")) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                        .opacity(0.5).clipped()
                } else {
                    // Filmstrip: each frame is placed by its SOURCE time within
                    // the clip's [sourceStart, sourceStart+duration] window — so
                    // trimming crops the strip (frames slide off) instead of
                    // squashing it.
                    GeometryReader { geo in
                        let n = clip.thumbs.count
                        let srcDur = max(clip.sourceDuration, 0.001)
                        let dur = max(clip.duration, 0.001)
                        let tw = geo.size.width * (srcDur / Double(n)) / dur
                        ForEach(Array(clip.thumbs.enumerated()), id: \.offset) { i, u in
                            let tau = (Double(i) + 0.5) / Double(n) * srcDur
                            AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.04) }
                                .frame(width: tw, height: geo.size.height).clipped()
                                .position(x: (tau - clip.sourceStart) / dur * geo.size.width,
                                          y: geo.size.height / 2)
                        }
                    }
                    .opacity(0.62)
                }
            }
            if kind == .audio { Waveform().stroke(Color.white.opacity(0.55), lineWidth: 1).padding(.vertical, 6) }
            Rectangle().fill(accent).frame(width: 3).frame(maxHeight: .infinity, alignment: .leading)
            Text(clip.label).font(.label(9)).tracking(0.5)
                .foregroundStyle(kind == .video ? .white : Theme.txtBody)
                .shadow(color: kind == .video ? .black : .clear, radius: 2)
                .lineLimit(1).padding(.horizontal, 7).padding(.vertical, 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? Theme.accentA(0.7) : .clear, lineWidth: 1.5))
        .frame(height: height)
    }
}

private struct BrickView: View {
    let brick: Brick; let laneHeight: CGFloat; let selected: Bool

    var body: some View {
        switch brick.kind {
        case .globalFX:
            ribbon(fill: LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                   stroke: Theme.lineStrong, text: brick.title, textColor: Theme.txt, height: laneHeight - 4, trailing: "▾")
        case .glassFX, .multiFX:
            ribbon(fill: LinearGradient(colors: [Theme.glassCyan.opacity(0.30), Theme.glassCyan.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing),
                   stroke: Theme.glassCyan, text: brick.title, textColor: Color(red: 0.9, green: 0.97, blue: 1), height: min(26, laneHeight * 0.52), chain: brick.isChain)
        case .bodyFX:
            ribbon(fill: LinearGradient(colors: [Theme.bodyViolet.opacity(0.32), Theme.bodyViolet.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing),
                   stroke: Theme.bodyViolet, text: brick.title, textColor: .white, height: min(26, laneHeight * 0.52), symbol: "person.fill")
        case .audioFX:
            ribbon(fill: LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                   stroke: Theme.lineHover, text: brick.title, textColor: Theme.txtBody, height: laneHeight - 6, symbol: "waveform")
        }
    }

    private func ribbon(fill: some ShapeStyle, stroke: Color, text: String, textColor: Color,
                        height: CGFloat, trailing: String? = nil, chain: Bool = false, symbol: String? = nil) -> some View {
        HStack(spacing: 4) {
            if chain { VStack(spacing: 1.5) { ForEach(0..<3) { _ in Capsule().fill(textColor).frame(width: 7, height: 1.5) } } }
            if let symbol { Image(systemName: symbol).font(.system(size: 8)).foregroundStyle(textColor) }
            Text(text.uppercased()).font(.label(8.5)).tracking(0.4).foregroundStyle(textColor).lineLimit(1)
            if let trailing { Spacer(minLength: 0); Text(trailing).font(.system(size: 9)).foregroundStyle(Theme.accent) }
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: Theme.rBrick).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: Theme.rBrick).strokeBorder(selected ? Theme.accentA(0.8) : stroke, lineWidth: 1))
        .padding(.top, 2)
    }
}

// MARK: - Trim handles (drag a selected clip's edges to set in/out)

private struct TrimHandles: View {
    let clip: Clip
    @ObservedObject var model: EditorModel
    let height: CGFloat
    @State private var orig: (tlStart: Double, srcStart: Double, dur: Double, srcDur: Double)?

    var body: some View {
        HStack(spacing: 0) {
            handle(leading: true)
            Spacer(minLength: 0)
            handle(leading: false)
        }
    }

    private func handle(leading: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Theme.accent)
            .frame(width: 18, height: height)
            .overlay(Capsule().fill(.white.opacity(0.85)).frame(width: 2.5, height: height * 0.4))
            .contentShape(Rectangle())
            .highPriorityGesture(
                // GLOBAL coordinate space: translation stays stable even as the
                // handle moves with the resizing clip — kills the jitter.
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { g in
                        if orig == nil { model.beginTrim(); orig = (clip.start, clip.sourceStart, clip.duration, clip.sourceDuration) }
                        guard let o = orig else { return }
                        let dx = Double(g.translation.width / PPS)
                        if leading {
                            // Left edge follows the finger, right edge fixed, and
                            // it STAYS (start moves, no re-anchor). A gap opens
                            // where the trimmed front was; the offset compensates.
                            let ns = min(max(o.srcStart + dx, 0), o.srcStart + o.dur - 0.3)
                            let change = ns - o.srcStart
                            model.setTrim(clip.id, start: o.tlStart + change, sourceStart: ns, duration: o.dur - change)
                        } else {
                            // move the out-point; start + in-point fixed
                            let nd = min(max(o.dur + dx, 0.3), o.srcDur - o.srcStart)
                            model.setTrim(clip.id, start: o.tlStart, sourceStart: o.srcStart, duration: nd)
                        }
                    }
                    .onEnded { _ in orig = nil; model.endTrim() }
            )
    }
}

private struct Playhead: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var engine: EngineStore
    var body: some View {
        VStack(spacing: 0) {
            Diamond().fill(Theme.accent).frame(width: 13, height: 13).shadow(color: Theme.accent, radius: 5)
            Rectangle().fill(Theme.accent).frame(width: 2).shadow(color: Theme.accentA(0.8), radius: 3)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - shapes

private struct Diamond: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.midY)); p.closeSubpath()
        }
    }
}

private struct Waveform: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            let n = Int(r.width / 3.4)
            for i in 0..<max(1, n) {
                let h = 6 + abs(sin(Double(i) * 0.7) * cos(Double(i) * 0.3)) * Double(r.height - 8)
                let x = r.minX + CGFloat(i) * 3.4
                p.move(to: CGPoint(x: x, y: r.midY - CGFloat(h)/2))
                p.addLine(to: CGPoint(x: x, y: r.midY + CGFloat(h)/2))
            }
        }
    }
}
