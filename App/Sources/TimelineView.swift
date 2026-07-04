//  TimelineView.swift
//  Horizontal multi-track timeline. Content clips + the four brick flavours, a
//  ruler with second ticks + a beat grid (from analyze_audio bpm) + chapter
//  markers, and a centred playhead. Tap to seek; auto-follows during playback.

import SwiftUI

private let PPS: CGFloat = 46          // pixels per second

private extension View {
    /// Apply a HIGH-PRIORITY gesture only when `active`. High priority so it wins
    /// over the timeline scrub (which has a smaller minimumDistance and would
    /// otherwise claim the drag first); gated so non-selected clips still scrub.
    @ViewBuilder func highPriorityGestureIf<G: Gesture>(_ active: Bool, _ g: G) -> some View {
        if active { highPriorityGesture(g) } else { self }
    }
}

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

/// One drag in flight on a clip. The zone is latched at grab time (desktop
/// pattern) and every update dispatches on it — never competing gestures.
private struct ClipDrag {
    enum Zone { case trimLeft, trimRight, move }
    let id: String
    let zone: Zone
    let start, srcStart, dur, srcDur, speed: Double   // clip's ORIGINAL span at grab
    var floor: Double = 0                             // trim walls (neighbor edges)
    var ceil: Double = .greatestFiniteMagnitude
    var snapHold: Double? = nil                       // move snap hysteresis latch
}

private struct TrackLane: View {
    let track: Track
    @ObservedObject var model: EditorModel
    @State private var drag: ClipDrag?

    private var laneHeight: CGFloat {
        switch track.kind { case .fxRail: 30; case .video: 52; case .lyric: 40; case .audio: 34 }
    }
    private var movingID: String? { drag?.zone == .move ? drag?.id : nil }

    /// THE desktop pattern: ONE gesture per clip. The grab position latches a
    /// zone — within 24pt of an edge (only if the clip is wider than 2× that) is
    /// a trim, otherwise the body moves. Edge beats body. Trim clamps to walls +
    /// source + snap; move sets a free start live (snap + hysteresis) and bounces
    /// on release if it overlaps a neighbor.
    private func clipDrag(_ clip: Clip) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("lane"))
            .onChanged { g in
                if drag == nil {
                    let localX = g.startLocation.x - CGFloat(clip.start) * PPS
                    let w = CGFloat(clip.duration) * PPS
                    let edge: CGFloat = 24
                    let zone: ClipDrag.Zone =
                        (w > 2 * edge && localX <= edge)       ? .trimLeft :
                        (w > 2 * edge && localX >= w - edge)   ? .trimRight : .move
                    var d = ClipDrag(id: clip.id, zone: zone, start: clip.start,
                                     srcStart: clip.sourceStart, dur: clip.duration,
                                     srcDur: clip.sourceDuration, speed: clip.speed)
                    if zone != .move {
                        let walls = model.trimWalls(excluding: clip.id, origStart: clip.start, origEnd: clip.end)
                        d.floor = walls.floor; d.ceil = walls.ceil
                    }
                    model.beginEdit()
                    drag = d
                }
                guard var d = drag, d.id == clip.id else { return }
                let dxSec = Double(g.translation.width / PPS)
                switch d.zone {
                case .trimLeft:
                    // in-point + start move together; walled + source-floored, edge snaps
                    let raw = d.start + dxSec
                    let srcFloor = d.srcDur > 0 ? d.start - d.srcStart / max(0.01, d.speed) : 0
                    var ns = model.snapEdge(raw, excluding: clip.id)
                    ns = max(d.floor, max(srcFloor, max(0, min(ns, (d.start + d.dur) - 0.3))))
                    let delta = ns - d.start
                    model.setTrim(clip.id, start: ns,
                                  sourceStart: max(0, d.srcStart + delta * d.speed),
                                  duration: d.dur - delta)
                case .trimRight:
                    // out-point only; capped by source length + right wall, edge snaps
                    let rawEnd = (d.start + d.dur) + dxSec
                    let maxEnd = d.srcDur > 0 ? d.start + (d.srcDur - d.srcStart) / max(0.01, d.speed) : rawEnd
                    var end = min(model.snapEdge(rawEnd, excluding: clip.id), min(maxEnd, d.ceil))
                    end = max(end, d.start + 0.3)
                    model.setTrim(clip.id, start: d.start, sourceStart: d.srcStart, duration: end - d.start)
                case .move:
                    // free start, snap with a hysteresis latch (no flicker)
                    let raw = d.start + dxSec
                    let escape = 0.2
                    var target = raw
                    if let held = d.snapHold, abs(raw - held) < escape {
                        target = held
                    } else {
                        let snapped = model.snapStart(raw, excluding: clip.id, duration: d.dur)
                        d.snapHold = abs(snapped - raw) > 0.0001 ? snapped : nil
                        target = snapped
                        drag = d
                    }
                    model.setClipStart(clip.id, max(0, target))
                }
            }
            .onEnded { _ in
                defer { drag = nil }
                guard let d = drag, d.id == clip.id else { return }
                switch d.zone {
                case .trimLeft, .trimRight: model.endEdit(clip.id)
                case .move: model.endMove(clip.id, originStart: d.start)
                }
            }
    }

    /// Same zone-dispatch as clips, minus the source in/out: move sets a free start
    /// (snap) and bounces on same-track brick overlap; trim moves an edge, walled by
    /// neighbour bricks. No composition rebuild (bricks don't drive the AVComposition).
    private func brickDrag(_ brick: Brick) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("lane"))
            .onChanged { g in
                if drag == nil {
                    let localX = g.startLocation.x - CGFloat(brick.start) * PPS
                    let w = CGFloat(brick.duration) * PPS
                    let edge: CGFloat = 20
                    let zone: ClipDrag.Zone =
                        (w > 2 * edge && localX <= edge)      ? .trimLeft :
                        (w > 2 * edge && localX >= w - edge)  ? .trimRight : .move
                    var d = ClipDrag(id: brick.id, zone: zone, start: brick.start,
                                     srcStart: 0, dur: brick.duration, srcDur: 0, speed: 1)
                    if zone != .move {
                        let walls = model.brickTrimWalls(brick.id, origStart: brick.start, origEnd: brick.end)
                        d.floor = walls.floor; d.ceil = walls.ceil
                    }
                    model.beginEdit()
                    drag = d
                }
                guard let d = drag, d.id == brick.id else { return }
                let dxSec = Double(g.translation.width / PPS)
                switch d.zone {
                case .trimLeft:
                    var ns = model.snapEdge(d.start + dxSec, excluding: brick.id)
                    ns = max(d.floor, max(0, min(ns, (d.start + d.dur) - 0.2)))
                    model.setBrickTrim(brick.id, start: ns, duration: d.dur - (ns - d.start))
                case .trimRight:
                    var end = min(model.snapEdge((d.start + d.dur) + dxSec, excluding: brick.id), d.ceil)
                    end = max(end, d.start + 0.2)
                    model.setBrickTrim(brick.id, start: d.start, duration: end - d.start)
                case .move:
                    let snapped = model.snapStart(d.start + dxSec, excluding: brick.id, duration: d.dur)
                    model.setBrickStart(brick.id, max(0, snapped))
                }
            }
            .onEnded { _ in
                defer { drag = nil }
                guard let d = drag, d.id == brick.id, d.zone == .move else { return }
                model.endBrickMove(brick.id, originStart: d.start)   // bounce on overlap
            }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if track.kind == .fxRail && track.bricks.isEmpty {
                Text("drop a brick here = global ▾")
                    .font(.label(8)).foregroundStyle(Theme.txtGhost).offset(x: 6, y: laneHeight/2 - 6)
            }
            ForEach(track.clips) { clip in
                let moving = drag?.id == clip.id && drag?.zone == .move
                let editable = track.kind == .video || track.kind == .lyric   // draggable/trimmable
                ContentClipView(clip: clip, kind: track.kind, selected: model.selectedID == clip.id, height: laneHeight)
                    .frame(width: CGFloat(clip.duration) * PPS)
                    .overlay {
                        if model.selectedID == clip.id && editable {
                            TrimHandles(height: laneHeight)   // decorative — the clip gesture does the work
                        }
                    }
                    .contentShape(Rectangle())
                    .scaleEffect(moving ? 1.05 : 1)
                    .shadow(color: moving ? Theme.accentA(0.5) : .clear, radius: 10)
                    .offset(x: CGFloat(clip.start) * PPS)   // move updates clip.start live
                    .zIndex(moving ? 2 : (model.selectedID == clip.id ? 1 : 0))
                    .highPriorityGestureIf(editable, clipDrag(clip))
                    .onTapGesture { model.selectedID = (model.selectedID == clip.id) ? nil : clip.id }
            }
            ForEach(track.bricks) { brick in
                let moving = drag?.id == brick.id && drag?.zone == .move
                BrickView(brick: brick, laneHeight: laneHeight,
                          selected: model.selectedID == brick.id)
                    .frame(width: CGFloat(brick.duration) * PPS)
                    .overlay {
                        if model.selectedID == brick.id { TrimHandles(height: laneHeight) }
                    }
                    .contentShape(Rectangle())
                    .scaleEffect(moving ? 1.05 : 1)
                    .shadow(color: moving ? Theme.accentA(0.5) : .clear, radius: 10)
                    .offset(x: CGFloat(brick.start) * PPS)
                    .zIndex(moving ? 2 : (model.selectedID == brick.id ? 1 : 0))
                    .highPriorityGesture(brickDrag(brick))
                    .onTapGesture { model.selectedID = (model.selectedID == brick.id) ? nil : brick.id }
            }
        }
        // Full content width so every offset clip is inside the lane's
        // hit-testable frame; named space lets the gesture read the grab zone.
        .frame(maxWidth: .infinity, minHeight: laneHeight, maxHeight: laneHeight, alignment: .topLeading)
        .coordinateSpace(.named("lane"))
        .sensoryFeedback(.impact(weight: .light), trigger: movingID)   // move pick-up / drop
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

/// Decorative edge grips shown on the selected clip — they mark the trim zones.
/// The actual trim is driven by the clip's single `clipDrag` gesture, so these
/// don't hit-test (no competing gesture).
private struct TrimHandles: View {
    let height: CGFloat
    var body: some View {
        HStack(spacing: 0) {
            bar; Spacer(minLength: 0); bar
        }
        .allowsHitTesting(false)
    }
    private var bar: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Theme.accent)
            .frame(width: 16, height: height)
            .overlay(Capsule().fill(.white.opacity(0.9)).frame(width: 2.5, height: height * 0.4))
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
