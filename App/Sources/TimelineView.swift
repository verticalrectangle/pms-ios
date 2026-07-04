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
            .highPriorityGesture(
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

    private var laneHeight: CGFloat {
        switch track.kind { case .fxRail: 30; case .video: 52; case .lyric: 40; case .audio: 34 }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if track.kind == .fxRail && track.bricks.isEmpty {
                Text("drop a brick here = global ▾")
                    .font(.label(8)).foregroundStyle(Theme.txtGhost).offset(x: 6, y: laneHeight/2 - 6)
            }
            ForEach(track.clips) { clip in
                ContentClipView(clip: clip, kind: track.kind, selected: model.selectedID == clip.id, height: laneHeight)
                    .frame(width: CGFloat(clip.duration) * PPS)
                    .offset(x: CGFloat(clip.start) * PPS)
                    .onTapGesture {
                        model.selectedID = (model.selectedID == clip.id) ? nil : clip.id
                    }
            }
            ForEach(track.bricks) { brick in
                BrickView(brick: brick, laneHeight: laneHeight,
                          selected: model.selectedID == brick.id)
                    .frame(width: CGFloat(brick.duration) * PPS)
                    .offset(x: CGFloat(brick.start) * PPS)
                    .onTapGesture { model.selectedID = brick.id }
            }
        }
        .frame(height: laneHeight, alignment: .topLeading)
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
                    HStack(spacing: 0) {   // filmstrip: sampled frames tiled across the clip
                        ForEach(clip.thumbs, id: \.self) { u in
                            AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.04) }
                                .frame(maxWidth: .infinity).frame(height: height).clipped()
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
