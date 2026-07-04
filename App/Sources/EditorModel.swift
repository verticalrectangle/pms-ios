//  EditorModel.swift
//  The editable projection of the open project. Holds the scene the screens render
//  and mutate; every mutation is applied optimistically AND pushed to the engine
//  through EngineStore.command(...) using the real levers. State that the engine
//  owns (playhead, playing, LUFS, busy) is read straight off EngineStore.

import SwiftUI
import Combine

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
        let v = VideoPlayback(engine: engine)
        v.onTick = { [weak self] time, playing in
            self?.playhead = time
            self?.isPlaying = playing
        }
        video = v
        Task {
            await v.load(url: url)
            videoDuration = v.duration
            playhead = 0
            // Replace the mock scene with the imported video as a real clip.
            let name = url.deletingPathExtension().lastPathComponent.uppercased() + ".MP4"
            let thumb = await VideoPlayback.thumbnail(for: url)
            let clip = Clip(id: "vclip", label: name, start: 0, duration: v.duration, thumbURL: thumb)
            tracks = [
                Track(id: "GFX", kind: .fxRail, name: "FX", clips: []),
                Track(id: "V1", kind: .video, name: "V1", clips: [clip]),
            ]
            selectedID = nil
            videoLoaded = true
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
