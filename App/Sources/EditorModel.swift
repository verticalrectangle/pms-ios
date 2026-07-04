//  EditorModel.swift
//  The editable projection of the open project. Holds the scene the screens render
//  and mutate; every mutation is applied optimistically AND pushed to the engine
//  through EngineStore.command(...) using the real levers. State that the engine
//  owns (playhead, playing, LUFS, busy) is read straight off EngineStore.

import SwiftUI
import Combine
import AVFoundation

@MainActor
final class EditorModel: ObservableObject {
    let engine: EngineStore
    let project: Project

    @Published var tracks: [Track]
    @Published var chapters: [ChapterMarker]
    @Published var selectedID: String?
    @Published var activeSheet: EditorSheet?
    @Published var format: Format
    @Published var bpm: Double
    @Published var beatsVisible = true

    // Authoritative playback state — the AVPlayer clock drives these when a
    // video is loaded (via onTick); otherwise optimistic + the engine.
    @Published var playhead: Double = 0
    @Published var isPlaying = false

    // Imported video (decoded through the engine's frame path).
    var video: VideoPlayback?
    @Published var videoLoaded = false
    @Published var videoDuration: Double?

    func importVideo(_ url: URL) {
        activeSheet = nil
        if video == nil {
            let v = VideoPlayback(engine: engine)
            v.onTick = { [weak self] time, playing in
                self?.playhead = time
                self?.isPlaying = playing
            }
            video = v
        }
        Task {
            let dur = (try? await AVURLAsset(url: url).load(.duration))?.seconds ?? 0
            guard dur > 0 else { return }
            playhead = 0
            let n = max(1, min(24, Int(dur / 1.5)))   // ~1 frame / 1.5s, capped
            let strip = await VideoPlayback.filmstrip(for: url, count: n)
            let clip = Clip(id: "vclip", label: "CLIP 1", start: 0, duration: dur,
                            thumbs: strip, sourceURL: url, sourceStart: 0, sourceDuration: dur)
            tracks = [
                Track(id: "GFX", kind: .fxRail, name: "FX", clips: []),
                Track(id: "V1", kind: .video, name: "V1", clips: [clip]),
            ]
            selectedID = nil
            videoDuration = dur
            videoLoaded = true
            await rebuildVideo()
        }
    }

    // MARK: Undo / redo (snapshots of the timeline)

    private var undoStack: [[Track]] = []
    private var redoStack: [[Track]] = []
    @Published var canUndo = false
    @Published var canRedo = false

    /// Snapshot the timeline before a mutating edit.
    private func snapshot() {
        undoStack.append(tracks)
        if undoStack.count > 60 { undoStack.removeFirst() }
        redoStack.removeAll()
        canUndo = true; canRedo = false
    }
    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(tracks)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { tracks = prev; selectedID = nil }
        canUndo = !undoStack.isEmpty; canRedo = true
        Task { await rebuildVideo() }
    }
    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(tracks)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { tracks = next; selectedID = nil }
        canUndo = true; canRedo = !redoStack.isEmpty
        Task { await rebuildVideo() }
    }

    // MARK: Clip editing (structural — rebuilds the AVComposition)

    private var videoTrackIndex: Int? { tracks.firstIndex { $0.kind == .video } }
    var selectedClip: Clip? {
        guard let ti = videoTrackIndex else { return nil }
        return tracks[ti].clips.first { $0.id == selectedID }
    }

    /// Rebuild the player timeline from the current video clips.
    func rebuildVideo(seekTo: Double? = nil) async {
        guard let ti = videoTrackIndex else { return }
        let segs = tracks[ti].clips.compactMap { c in
            c.sourceURL.map { VideoPlayback.Segment(url: $0, sourceStart: c.sourceStart, duration: c.duration) }
        }
        await video?.load(segments: segs, seekTo: seekTo)
        videoDuration = video?.duration
    }

    /// Lay the video clips end-to-end (contiguous from 0) and renumber.
    private func relayoutVideoClips() {
        guard let ti = videoTrackIndex else { return }
        var cursor = 0.0
        for i in tracks[ti].clips.indices {
            tracks[ti].clips[i].start = cursor
            tracks[ti].clips[i].label = "CLIP \(i + 1)"
            cursor += tracks[ti].clips[i].duration
        }
    }

    /// Split the clip under the playhead into two (structural — same footage).
    func splitAtPlayhead() {
        guard let ti = videoTrackIndex,
              let ci = tracks[ti].clips.firstIndex(where: { playhead > $0.start + 0.1 && playhead < $0.end - 0.1 })
        else { return }
        snapshot()
        let c = tracks[ti].clips[ci]
        let off = playhead - c.start
        // Both halves keep the FULL source filmstrip — ContentClipView crops it
        // to each clip's [sourceStart, sourceStart+duration] range by source time.
        var a = c; a.duration = off
        let b = Clip(id: c.id + "_s\(Int(playhead * 1000))", label: c.label,
                     start: playhead, duration: c.duration - off, seed: c.seed,
                     thumbs: c.thumbs,
                     sourceURL: c.sourceURL, sourceStart: c.sourceStart + off,
                     sourceDuration: c.sourceDuration)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            tracks[ti].clips.replaceSubrange(ci...ci, with: [a, b])
            relayoutVideoClips()          // fix start positions + renumber labels
            selectedID = b.id
        }
        // composition unchanged (a+b == original) → no reload needed
    }

    // MARK: Trim (drag the clip edges)

    func beginTrim() { snapshot() }
    /// On release, re-anchor the clips to 0 AND shift the playhead back by how
    /// far front-trim moved the first clip — so the footage under the playhead
    /// stays put (no visible jump) while the clip settles at the origin.
    func endTrim() {
        guard let ti = videoTrackIndex else { return }
        let change = tracks[ti].clips.first?.start ?? 0   // front-trim's leftward displacement
        let target = max(0, playhead - change)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            relayoutVideoClips()
            playhead = target                              // set synchronously so the offset compensates
        }
        Task { await rebuildVideo(seekTo: target) }
    }

    /// Set a clip's timeline position + in-point + length (the trim handle
    /// computes these). Left-trim moves `start` so the left edge follows the
    /// finger (right edge fixed); right-trim keeps `start`. No relayout during
    /// the drag (that jitters); positions settle + composition rebuilds on end.
    func setTrim(_ id: String, start: Double, sourceStart: Double, duration: Double) {
        guard let ti = videoTrackIndex, let ci = tracks[ti].clips.firstIndex(where: { $0.id == id }) else { return }
        tracks[ti].clips[ci].start = start
        tracks[ti].clips[ci].sourceStart = sourceStart
        tracks[ti].clips[ci].duration = duration
    }

    /// Delete the selected clip; remaining clips close the gap.
    func deleteSelectedClip() {
        guard let ti = videoTrackIndex, let id = selectedID else { return }
        snapshot()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            tracks[ti].clips.removeAll { $0.id == id }
            selectedID = nil
        }
        if tracks[ti].clips.isEmpty {
            video?.stop(); video = nil
            videoLoaded = false; videoDuration = nil; playhead = 0; isPlaying = false
        } else {
            relayoutVideoClips()
            Task { await rebuildVideo() }
        }
    }

    init(project: Project, engine: EngineStore) {
        self.project = project
        self.engine = engine
        self.tracks = Sample.tracks
        self.chapters = Sample.chapters
        self.format = project.format
        self.bpm = Sample.bpm
        engine.command("load_project", ["path": project.id])   // stand-in
    }

    var duration: Double { videoDuration ?? project.duration }

    // MARK: Derived

    /// Bricks whose time range contains `t` — drives the canvas badges + look.
    func activeBricks(at t: Double) -> [Brick] {
        tracks.flatMap { $0.bricks }.filter { t >= $0.start && t < $0.end }
    }

    func activeVideoLabel(at t: Double) -> String {
        guard let v = tracks.first(where: { $0.kind == .video }) else { return "CLIP" }
        return (v.clips.first { t >= $0.start && t < $0.end } ?? v.clips.last)?.label ?? "CLIP"
    }

    func selection() -> (track: Track, brick: Brick)? {
        for tr in tracks { if let b = tr.bricks.first(where: { $0.id == selectedID }) { return (tr, b) } }
        return nil
    }

    func binding(forBrick id: String) -> Binding<Brick>? {
        guard let ti = tracks.firstIndex(where: { $0.bricks.contains { $0.id == id } }),
              let bi = tracks[ti].bricks.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.tracks[ti].bricks[bi] },
            set: { self.tracks[ti].bricks[bi] = $0 }
        )
    }

    // MARK: Transport (levers)

    func togglePlay() {
        isPlaying.toggle()
        if let v = video { isPlaying ? v.play() : v.pause() }   // onTick reconciles
        else { engine.command(isPlaying ? "play" : "pause") }
    }
    func seek(_ t: Double) {
        let v = min(max(t, 0), duration)
        playhead = v
        if let vid = video { vid.seek(v) } else { engine.command("seek", ["time": v]) }
    }
    /// Pause playback when the user grabs the timeline to scrub.
    func pauseForScrub() {
        if isPlaying { video?.pause(); isPlaying = false; if video == nil { engine.command("pause") } }
    }

    // MARK: Mutations → levers

    /// Drop an effect. On a video clip → glass (add_effect_brick, welds after 1.5s).
    /// On the FX rail → global. Body/audio effects use their own levers.
    func placeEffect(_ effect: EffectDef, onto target: DropTarget, at t: Double) {
        let nid = "\(effect.id)_\(Int(Date().timeIntervalSince1970 * 1000) % 100000)"
        var params = Dictionary(uniqueKeysWithValues: effect.params.map { ($0.key, $0.def) })

        switch target {
        case .clip(let clipID):
            let kind: BrickKind = effect.category == "Body" ? .bodyFX : .glassFX
            let lever = effect.category == "Body"
                ? (effect.id == "rvm_matte" ? "remove_background" : "add_body_fx_brick")
                : "add_effect_brick"
            insertBrick(Brick(id: nid, kind: kind, start: t, duration: 2, chain: [effect.id],
                              boundClipID: clipID, params: params), onTrackWithClip: clipID)
            engine.command(lever, ["effect": effect.id, "clip": clipID, "start": t, "params": params])
            selectedID = nid

        case .fxRail:
            insertBrick(Brick(id: nid, kind: .globalFX, start: t, duration: 3, chain: [effect.id], params: params),
                        onTrackKind: .fxRail)
            engine.command("add_effect_brick", ["effect": effect.id, "track": "GFX", "start": t, "global": true, "params": params])
            selectedID = nid

        case .audioClip(let clipID):
            insertBrick(Brick(id: nid, kind: .audioFX, start: t, duration: 4, chain: [effect.id],
                              boundClipID: clipID, params: params), onTrackWithClip: clipID)
            engine.command("add_audio_multifx_brick", ["effects": [effect.id], "clip": clipID, "start": t])
            selectedID = nid

        case .brick(let brickID):
            weld(effect.id, intoBrick: brickID)
        }
        _ = params
    }

    /// Weld an effect into an existing brick → Multi-FX chain (add_multifx_brick semantics).
    func weld(_ effectID: String, intoBrick brickID: String) {
        guard let b = binding(forBrick: brickID) else { return }
        b.wrappedValue.chain.append(effectID)
        if b.wrappedValue.kind == .glassFX { b.wrappedValue.kind = .multiFX }
        engine.command("add_multifx_brick", ["brick": brickID, "effects": b.wrappedValue.chain])
        selectedID = brickID
    }

    /// Decouple a welded brick back to a free-floating glass brick.
    func decouple(_ brickID: String) {
        guard let b = binding(forBrick: brickID) else { return }
        b.wrappedValue.boundClipID = nil
        engine.command("decouple_fx_brick", ["brick": brickID])
    }

    func setParam(_ key: String, _ value: Double, onBrick id: String) {
        guard let b = binding(forBrick: id) else { return }
        b.wrappedValue.params[key] = value
        engine.command("set_clip_fx", ["brick": id, "params": [key: value]])
    }

    func deleteBrick(_ id: String) {
        for i in tracks.indices { tracks[i].bricks.removeAll { $0.id == id } }
        engine.command("delete_clip", ["clip": id])
        if selectedID == id { selectedID = nil }
    }

    // MARK: AI actions (each is one lever + a local model; drives the busy bar)

    func run(_ action: AIAction) {
        activeSheet = nil
        engine.command(action.lever, [:])
        engine.simulateBusy(label: action.busyLabel)      // mirrors the `busy` event
    }

    // MARK: private

    private func insertBrick(_ brick: Brick, onTrackWithClip clipID: String) {
        guard let ti = tracks.firstIndex(where: { $0.clips.contains { $0.id == clipID } }) else { return }
        tracks[ti].bricks.append(brick)
    }
    private func insertBrick(_ brick: Brick, onTrackKind kind: TrackKind) {
        guard let ti = tracks.firstIndex(where: { $0.kind == kind }) else { return }
        tracks[ti].bricks.append(brick)
    }
}

enum EditorSheet: Identifiable {
    case media, fx, lyrics, agent, export
    var id: Int { hashValue }
}

enum DropTarget {
    case clip(String)       // glass FX bind
    case audioClip(String)  // audio FX
    case fxRail             // global FX
    case brick(String)      // weld into chain
}
