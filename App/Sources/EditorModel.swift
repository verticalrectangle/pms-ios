//  EditorModel.swift
//  The editable projection of the open project. Holds the scene the screens render
//  and mutate; every mutation is applied optimistically AND pushed to the engine
//  through EngineStore.command(...) using the real levers. State that the engine
//  owns (playhead, playing, LUFS, busy) is read straight off EngineStore.

import SwiftUI
import Combine
import AVFoundation
import UIKit

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
    @Published var focusNewText = false   // keyboard pops only right after CREATING a title, not on select

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
            // Copy the picked file into the project's durable media/ dir (was temp).
            let media = ProjectStore.importMedia(url, into: project.id)
            let n = max(1, min(24, Int(dur / 1.5)))   // ~1 frame / 1.5s, capped
            let strip = await VideoPlayback.filmstrip(for: media, count: n)
            let id = "v_\(UUID().uuidString.prefix(6))"

            if videoLoaded, let ti = videoTrackIndex, !tracks[ti].clips.isEmpty {
                // APPEND after the last clip — builds a multi-clip sequence.
                // (videoLoaded, NOT "has clips" — the initial timeline is Sample
                //  mock data, so the first real import must replace it, not append.)
                let startAt = tracks[ti].clips.map(\.end).max() ?? 0
                let clip = Clip(id: id, label: "CLIP", start: startAt, duration: dur,
                                thumbs: strip, sourceURL: media, sourceStart: 0, sourceDuration: dur)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    tracks[ti].clips.append(clip)
                    renumberLabels()
                    selectedID = clip.id
                }
            } else {
                // FIRST import — lay down the tracks.
                playhead = 0
                let clip = Clip(id: id, label: "CLIP 1", start: 0, duration: dur,
                                thumbs: strip, sourceURL: media, sourceStart: 0, sourceDuration: dur)
                tracks = [
                    Track(id: "GFX", kind: .fxRail, name: "FX", clips: []),
                    Track(id: "V1", kind: .video, name: "V1", clips: [clip]),
                ]
                selectedID = nil
            }
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
    /// The track holding a clip (any kind) — drag ops operate on all tracks, not
    /// just video, so text/other bricks move + trim the same way.
    private func trackIndex(ofClip id: String) -> Int? {
        tracks.firstIndex { $0.clips.contains { $0.id == id } }
    }
    func trackKind(ofClip id: String) -> TrackKind? {
        trackIndex(ofClip: id).map { tracks[$0].kind }
    }
    var selectedClip: Clip? {
        guard let ti = videoTrackIndex else { return nil }
        return tracks[ti].clips.first { $0.id == selectedID }
    }

    /// Title/lyric clips to bake into the export overlay.
    var titleClips: [Clip] { tracks.first { $0.kind == .lyric }?.clips ?? [] }

    /// The current video clips as export/playback segments.
    var videoSegments: [VideoPlayback.Segment] {
        (tracks.first { $0.kind == .video }?.clips ?? []).compactMap { c in
            c.sourceURL.map { VideoPlayback.Segment(url: $0, start: c.start, sourceStart: c.sourceStart, duration: c.duration, fadeIn: c.fadeIn, fadeOut: c.fadeOut) }
        }
    }

    /// Rebuild the player timeline from the current video clips.
    func rebuildVideo(seekTo: Double? = nil) async {
        guard let ti = videoTrackIndex else { return }
        let segs = tracks[ti].clips.compactMap { c in
            c.sourceURL.map { VideoPlayback.Segment(url: $0, start: c.start, sourceStart: c.sourceStart, duration: c.duration, fadeIn: c.fadeIn, fadeOut: c.fadeOut) }
        }
        await video?.load(segments: segs, seekTo: seekTo)
        videoDuration = video?.duration
    }

    /// Renumber labels by order — WITHOUT moving any clip. Edits are local: a
    /// split cuts in place, a delete leaves its gap, nothing else shifts.
    private func renumberLabels() {
        guard let ti = videoTrackIndex else { return }
        for i in tracks[ti].clips.indices { tracks[ti].clips[i].label = "CLIP \(i + 1)" }
    }

    /// Split the SELECTED item under the playhead into two — a clip (any kind) OR
    /// an FX brick. Structural; same footage / text / chain in each half.
    func splitAtPlayhead() {
        guard let r = selectedRef else { return }
        if r.kind == .brick { splitBrickAtPlayhead(r); return }
        let ti = r.track
        guard let ci = tracks[ti].clips.firstIndex(where: { playhead > $0.start + 0.1 && playhead < $0.end - 0.1 })
        else { return }
        snapshot()
        let c = tracks[ti].clips[ci]
        let off = playhead - c.start
        // Both halves keep the FULL source filmstrip — ContentClipView crops it
        // to each clip's [sourceStart, sourceStart+duration] range by source time.
        var a = c; a.duration = off; a.fadeOut = 0        // fade-out belongs to the tail now
        var b = Clip(id: c.id + "_s\(Int(playhead * 1000))", label: c.label,
                     start: playhead, duration: c.duration - off, seed: c.seed,
                     thumbs: c.thumbs,
                     sourceURL: c.sourceURL, sourceStart: c.sourceStart + off * c.speed,
                     sourceDuration: c.sourceDuration, speed: c.speed)
        b.fadeIn = 0; b.fadeOut = c.fadeOut               // fade-in stayed with the head
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            tracks[ti].clips.replaceSubrange(ci...ci, with: [a, b])   // a+b occupy c's exact span
            if tracks[ti].kind == .video { renumberLabels() }         // text keeps its words
            selectedID = b.id
        }
        // composition unchanged (a+b == original span & net fade) → no reload needed
    }

    /// Split an FX brick at the playhead — chain/params/binding carry to both halves.
    private func splitBrickAtPlayhead(_ r: ItemRef) {
        let b = tracks[r.track].bricks[r.index]
        guard playhead > b.start + 0.1, playhead < b.end - 0.1 else { return }
        snapshot()
        var left = b; left.duration = playhead - b.start
        var right = b; right.id = regenID(b.id); right.start = playhead; right.duration = b.end - playhead
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            tracks[r.track].bricks.replaceSubrange(r.index...r.index, with: [left, right])
            selectedID = right.id
        }
    }

    // MARK: Free-position drag (the desktop model: free start/end, implicit
    // gaps, wall-clamp, snap — one Clip struct, index-independent).

    private let snapRadius = 0.17   // ≈ 8px @ PPS 46 (desktop SNAP_PX / zoom)

    func beginEdit() { snapshot() }                 // one undo step per drag
    func endEdit(_ id: String) { if trackKind(ofClip: id) == .video { Task { await rebuildVideo() } } }

    /// Lines a dragged edge snaps to: playhead, 0, every OTHER clip's AND brick's edges.
    private func snapCandidates(excluding id: String) -> [Double] {
        var c: [Double] = [playhead, 0]
        for tr in tracks {
            for cl in tr.clips  where cl.id != id { c.append(cl.start); c.append(cl.end) }
            for b  in tr.bricks where b.id  != id { c.append(b.start);  c.append(b.end) }
        }
        return c
    }
    /// Snap a single edge to the nearest candidate within the radius.
    func snapEdge(_ t: Double, excluding id: String) -> Double {
        var best = t, dt = snapRadius
        for c in snapCandidates(excluding: id) where abs(c - t) < dt { dt = abs(c - t); best = c }
        return best
    }
    /// Snap a body move — whichever of the clip's two edges is closest wins.
    func snapStart(_ t: Double, excluding id: String, duration dur: Double) -> Double {
        var best = t, dt = snapRadius
        for c in snapCandidates(excluding: id) {
            if abs(c - t) < dt         { dt = abs(c - t);         best = c }
            if abs(c - (t + dur)) < dt { dt = abs(c - (t + dur)); best = c - dur }
        }
        return best
    }
    /// Walls: an edge can't cross a same-track neighbor. floor = max end of clips
    /// left of the dragged clip's ORIGINAL span, ceil = min start of clips right.
    func trimWalls(excluding id: String, origStart: Double, origEnd: Double) -> (floor: Double, ceil: Double) {
        guard let ti = trackIndex(ofClip: id) else { return (0, .greatestFiniteMagnitude) }
        var floor = 0.0, ceil = Double.greatestFiniteMagnitude
        for oc in tracks[ti].clips where oc.id != id {
            if oc.end   <= origStart + 0.001 { floor = max(floor, oc.end) }
            if oc.start >= origEnd   - 0.001 { ceil  = min(ceil, oc.start) }
        }
        return (floor, ceil)
    }

    /// Plain setter — the trim gesture has already clamped to walls + source.
    func setTrim(_ id: String, start: Double, sourceStart: Double, duration: Double) {
        guard let ti = trackIndex(ofClip: id), let ci = tracks[ti].clips.firstIndex(where: { $0.id == id }) else { return }
        tracks[ti].clips[ci].start = max(0, start)
        tracks[ti].clips[ci].sourceStart = max(0, sourceStart)
        tracks[ti].clips[ci].duration = max(0.3, duration)
    }

    // MARK: Brick drag — no source in/out, no composition rebuild. Bricks can't
    // overlap OTHER BRICKS on the same track (they may coexist with clips).

    func setBrickStart(_ id: String, _ start: Double) {
        guard let r = locate(id), r.kind == .brick else { return }
        tracks[r.track].bricks[r.index].start = max(0, start)
    }
    func setBrickTrim(_ id: String, start: Double, duration: Double) {
        guard let r = locate(id), r.kind == .brick else { return }
        tracks[r.track].bricks[r.index].start = max(0, start)
        tracks[r.track].bricks[r.index].duration = max(0.15, duration)
    }
    /// Same-track brick-vs-brick overlap (half-open).
    func brickConflicts(_ id: String) -> Bool {
        guard let r = locate(id), r.kind == .brick else { return false }
        let b = tracks[r.track].bricks[r.index]
        return tracks[r.track].bricks.contains { $0.id != id && b.start < $0.end && b.end > $0.start }
    }
    /// Trim walls from same-track neighbour BRICKS (a brick edge can't cross one).
    func brickTrimWalls(_ id: String, origStart: Double, origEnd: Double) -> (floor: Double, ceil: Double) {
        guard let r = locate(id), r.kind == .brick else { return (0, .greatestFiniteMagnitude) }
        var floor = 0.0, ceil = Double.greatestFiniteMagnitude
        for ob in tracks[r.track].bricks where ob.id != id {
            if ob.end   <= origStart + 0.001 { floor = max(floor, ob.end) }
            if ob.start >= origEnd   - 0.001 { ceil  = min(ceil, ob.start) }
        }
        return (floor, ceil)
    }
    /// Release: bounce back to the origin if the brick overlaps a same-track brick.
    func endBrickMove(_ id: String, originStart: Double) {
        if brickConflicts(id) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { setBrickStart(id, originStart) }
        }
    }

    // MARK: Fades (live value; rebuild the composition on release)

    func setFade(_ id: String, fadeIn: Double? = nil, fadeOut: Double? = nil) {
        guard let ti = trackIndex(ofClip: id), let ci = tracks[ti].clips.firstIndex(where: { $0.id == id }) else { return }
        if let fadeIn  { tracks[ti].clips[ci].fadeIn  = max(0, fadeIn) }
        if let fadeOut { tracks[ti].clips[ci].fadeOut = max(0, fadeOut) }
    }
    func commitFade() { Task { await rebuildVideo() } }

    // MARK: Body move — free set-start, overlap allowed live, bounced on release

    /// Live during the drag (no rebuild) — the clip's start follows the finger.
    func setClipStart(_ id: String, _ newStart: Double) {
        guard let ti = trackIndex(ofClip: id), let ci = tracks[ti].clips.firstIndex(where: { $0.id == id }) else { return }
        tracks[ti].clips[ci].start = max(0, newStart)
    }
    /// Same-track overlap, half-open (desktop clips_conflict).
    func clipConflicts(_ id: String) -> Bool {
        guard let ti = trackIndex(ofClip: id), let c = tracks[ti].clips.first(where: { $0.id == id }) else { return false }
        return tracks[ti].clips.contains { $0.id != id && c.start < $0.end && c.end > $0.start }
    }
    /// Release: bounce back to the origin on overlap, else keep. Rebuild the
    /// composition only for video clips (text is an overlay — no reload).
    func endMove(_ id: String, originStart: Double) {
        if clipConflicts(id) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { setClipStart(id, originStart) }
        }
        if trackKind(ofClip: id) == .video { Task { await rebuildVideo() } }
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
            renumberLabels()              // leave the gap; don't shift other clips
            Task { await rebuildVideo() }
        }
    }

    init(project: Project, engine: EngineStore) {
        self.project = project
        self.engine = engine
        if let doc = ProjectStore.load(project.id) {          // saved project → hydrate from .pms
            self.tracks = doc.tracks
            self.chapters = doc.chapters
            self.format = doc.format
            self.bpm = doc.bpm
        } else if project.isNew {                             // fresh empty project
            self.tracks = []; self.chapters = []
            self.format = project.format; self.bpm = Sample.bpm
        } else {                                              // demo card (no saved doc yet)
            self.tracks = Sample.tracks; self.chapters = Sample.chapters
            self.format = project.format; self.bpm = Sample.bpm
        }
        if tracks.contains(where: { $0.kind == .video && !$0.clips.isEmpty }) {
            Task { await hydrateVideo() }                     // rebuild player + filmstrips
        }
    }

    /// Rebuild the AVPlayer + regenerate filmstrips (thumbs aren't persisted) from
    /// the loaded video clips.
    private func hydrateVideo() async {
        guard let ti = videoTrackIndex, !tracks[ti].clips.isEmpty else { return }
        if video == nil {
            let v = VideoPlayback(engine: engine)
            v.onTick = { [weak self] time, playing in self?.playhead = time; self?.isPlaying = playing }
            video = v
        }
        for ci in tracks[ti].clips.indices {
            let c = tracks[ti].clips[ci]
            if c.thumbs.isEmpty, let url = c.sourceURL {
                let n = max(1, min(24, Int(c.sourceDuration / 1.5)))
                let strip = await VideoPlayback.filmstrip(for: url, count: n)
                if ti < tracks.count, ci < tracks[ti].clips.count { tracks[ti].clips[ci].thumbs = strip }
            }
        }
        videoLoaded = true
        await rebuildVideo()
    }

    /// Persist the project to its .pms (media already lives in the project's media/ dir).
    func save() {
        guard !tracks.isEmpty || ProjectStore.exists(project.id) else { return }
        var t = tracks
        for ti in t.indices {
            for ci in t[ti].clips.indices {
                t[ti].clips[ci].mediaFile = t[ti].clips[ci].sourceURL?.lastPathComponent
            }
        }
        let doc = ProjectDoc(name: project.name, format: format, bpm: bpm,
                             duration: duration, tracks: t, chapters: chapters)
        ProjectStore.save(doc, id: project.id)
        Task { await writePoster() }
    }

    /// First-frame poster for the Home card.
    private func writePoster() async {
        guard let v = tracks.first(where: { $0.kind == .video }),
              let c = v.clips.first, let url = c.sourceURL else { return }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 300, height: 400)
        let at = CMTime(seconds: c.sourceStart + 0.1, preferredTimescale: 600)
        if let cg = try? await gen.image(at: at).image,
           let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.72) {
            ProjectStore.writePoster(data, id: project.id)
        }
    }

    var duration: Double { videoDuration ?? project.duration }

    // MARK: Derived

    /// Bricks whose time range contains `t` — drives the canvas badges + look.
    func activeBricks(at t: Double) -> [Brick] {
        tracks.flatMap { $0.bricks }.filter { t >= $0.start && t < $0.end }
    }

    func activeVideoLabel(at t: Double) -> String {
        guard let v = tracks.first(where: { $0.kind == .video }), !v.clips.isEmpty else { return "" }
        return (v.clips.first { t >= $0.start && t < $0.end } ?? v.clips.last)?.label ?? ""
    }

    // MARK: Text / lyric clips (rendered as canvas overlays; preview now, bake later)

    /// Text clips (lyric track) whose span contains `t` — drives the canvas title.
    func activeLyrics(at t: Double) -> [Clip] {
        tracks.first { $0.kind == .lyric }?.clips.filter { t >= $0.start && t < $0.end } ?? []
    }
    var selectedLyricClip: Clip? {
        tracks.first { $0.kind == .lyric }?.clips.first { $0.id == selectedID }
    }
    /// Add a text clip at the playhead (creates the text track if needed) + select it.
    func addTextClip() {
        activeSheet = nil
        snapshot()
        let clip = Clip(id: "t_\(UUID().uuidString.prefix(6))", label: "YOUR TEXT",
                        start: playhead, duration: 3)
        if let ti = tracks.firstIndex(where: { $0.kind == .lyric }) {
            tracks[ti].clips.append(clip)
        } else {
            // Text track sits ABOVE video (lower index = frontmost layer).
            tracks.insert(Track(id: "TXT", kind: .lyric, name: "TEXT", clips: [clip]),
                          at: videoTrackIndex ?? tracks.count)
        }
        selectedID = clip.id
        focusNewText = true   // just created → open the keyboard; selecting later won't
    }
    func setClipText(_ id: String, _ text: String) {
        for ti in tracks.indices where tracks[ti].kind == .lyric {
            if let ci = tracks[ti].clips.firstIndex(where: { $0.id == id }) {
                tracks[ti].clips[ci].label = text; return
            }
        }
    }
    /// Delete a clip on any non-video track (text/audio) — video uses deleteSelectedClip.
    func deleteClipAnywhere(_ id: String) {
        snapshot()
        for ti in tracks.indices { tracks[ti].clips.removeAll { $0.id == id } }
        if selectedID == id { selectedID = nil }
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

    // MARK: - Universal item ops (one address + one clipboard for clips AND bricks)

    enum ItemKind { case clip, brick }
    /// The address of a timeline item. Resolve-on-demand — never store across a
    /// mutation (indices shift when arrays change).
    struct ItemRef { let id: String; let track: Int; let index: Int; let kind: ItemKind }

    func locate(_ id: String) -> ItemRef? {
        for (ti, tr) in tracks.enumerated() {
            if let ci = tr.clips.firstIndex(where: { $0.id == id })  { return ItemRef(id: id, track: ti, index: ci, kind: .clip) }
            if let bi = tr.bricks.firstIndex(where: { $0.id == id }) { return ItemRef(id: id, track: ti, index: bi, kind: .brick) }
        }
        return nil
    }
    var selectedRef: ItemRef? { selectedID.flatMap(locate) }

    /// Which action bar the current selection routes to — the ONE resolver that
    /// replaces the three clip-privileged ones (fixes the audio-clip dead end:
    /// an audio clip now routes to .clip → ClipActionBar).
    enum SelectionBar { case none; case clip(Clip); case lyric(Clip); case brick(Brick) }
    var selectedBar: SelectionBar {
        guard let r = selectedRef else { return .none }
        switch r.kind {
        case .clip:  let c = tracks[r.track].clips[r.index]
                     return tracks[r.track].kind == .lyric ? .lyric(c) : .clip(c)
        case .brick: return .brick(tracks[r.track].bricks[r.index])
        }
    }

    struct ClipboardItem { enum Payload { case clip(Clip); case brick(Brick) }; let payload: Payload; let trackKind: TrackKind }
    @Published var clipboard: ClipboardItem?

    private func regenID(_ old: String) -> String { "\(old.prefix(4))_\(UUID().uuidString.prefix(6))" }

    func copyItem(_ id: String? = nil) {
        guard let r = (id ?? selectedID).flatMap(locate) else { return }
        let kind = tracks[r.track].kind
        clipboard = r.kind == .clip
            ? ClipboardItem(payload: .clip(tracks[r.track].clips[r.index]),  trackKind: kind)
            : ClipboardItem(payload: .brick(tracks[r.track].bricks[r.index]), trackKind: kind)
    }
    func cutItem(_ id: String? = nil) {
        guard let r = (id ?? selectedID).flatMap(locate) else { return }
        copyItem(r.id); deleteSelected(r.id)     // deleteSelected snapshots → one undo step
    }
    /// Paste lands at the PLAYHEAD (NLE convention).
    func pasteItem() {
        guard let cb = clipboard else { return }
        switch cb.payload {
        case .clip(let c):  insertClipCopy(c,  ofKind: cb.trackKind, at: playhead)
        case .brick(let b): insertBrickCopy(b, ofKind: cb.trackKind, at: playhead, keepBinding: false)
        }
    }
    /// Duplicate lands right AFTER the original (desktop duplicate).
    func duplicateItem(_ id: String? = nil) {
        guard let r = (id ?? selectedID).flatMap(locate) else { return }
        if r.kind == .clip { let c = tracks[r.track].clips[r.index]
                             insertClipCopy(c, ofKind: tracks[r.track].kind, at: c.end) }
        else               { let b = tracks[r.track].bricks[r.index]
                             insertBrickCopy(b, ofKind: tracks[r.track].kind, at: b.end, keepBinding: true) }
    }

    /// First start ≥ preferred with no same-track clip overlap (clips can't stack).
    private func firstFreeStart(onTrack ti: Int, preferred: Double, duration: Double) -> Double {
        var start = max(0, preferred), moved = true
        while moved { moved = false
            for o in tracks[ti].clips where start < o.end && start + duration > o.start { start = o.end; moved = true }
        }
        return start
    }

    private func insertClipCopy(_ src: Clip, ofKind kind: TrackKind, at t: Double) {
        guard let ti = tracks.firstIndex(where: { $0.kind == kind }) else { return }
        snapshot()
        var c = src; c.id = regenID(src.id)
        c.start = firstFreeStart(onTrack: ti, preferred: t, duration: c.duration)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            tracks[ti].clips.append(c)
            if kind == .video { renumberLabels() }   // text keeps its words
            selectedID = c.id
        }
        if kind == .video { Task { await rebuildVideo() } }   // composition must include it
    }

    private func insertBrickCopy(_ src: Brick, ofKind kind: TrackKind, at t: Double, keepBinding: Bool) {
        guard let ti = tracks.firstIndex(where: { $0.kind == kind }) else { return }
        snapshot()
        var b = src; b.id = regenID(src.id); b.start = t   // bricks may overlap → exact playhead
        if !keepBinding { b.boundClipID = nil }            // paste = free brick; engine re-welds
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            tracks[ti].bricks.append(b); selectedID = b.id
        }
    }

    /// Universal delete — any clip (with video teardown) or brick.
    func deleteSelected(_ id: String? = nil) {
        guard let r = (id ?? selectedID).flatMap(locate) else { return }
        snapshot()
        let ti = r.track, wasVideo = tracks[ti].kind == .video && r.kind == .clip
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            if r.kind == .clip { tracks[ti].clips.removeAll { $0.id == r.id } }
            else               { tracks[ti].bricks.removeAll { $0.id == r.id } }
            if selectedID == r.id { selectedID = nil }
        }
        if wasVideo {
            if tracks[ti].clips.isEmpty {
                video?.stop(); video = nil
                videoLoaded = false; videoDuration = nil; playhead = 0; isPlaying = false
            } else { renumberLabels(); Task { await rebuildVideo() } }
        }
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
