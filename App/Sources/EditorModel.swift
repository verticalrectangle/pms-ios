//  EditorModel.swift
//  The editable projection of the open project. The ENGINE owns the timeline:
//  every structural mutation goes through EngineStore.result(...) with integer
//  (track, clip) addresses, then the projection is re-decoded from
//  get_project(verbose: true). Local state exists only as
//    - a render cache of the last snapshot (tracks/chapters/format/bpm), and
//    - live-gesture optimism (a drag updates the cache at 60 fps; the engine
//      lever is sent once, on gesture end, then the projection refreshes).
//  Undo/redo are the engine's. AVFoundation (VideoPlayback) is a decode/preview
//  backend fed FROM the projection — it never owns clip timing.
//
//  Transport: the engine owns transport STATE (play/pause/seek land in
//  AppState), but on iOS the engine has no audio clock (pms_tick does not
//  advance the playhead), so while media is loaded the AVPlayer remains the
//  fine-grained clock and the engine playhead is reconciled at ~5 Hz + on
//  every boundary (play/pause/seek). With no media, engine events drive time.

import SwiftUI
import Combine
import AVFoundation
import UIKit

@MainActor
final class EditorModel: ObservableObject {
    let engine: EngineStore
    let project: Project

    // Projection cache (rendered by screens; re-derived from the engine).
    @Published var tracks: [Track] = []
    @Published var chapters: [ChapterMarker] = []
    @Published var selectedID: String? {
        didSet { if oldValue != selectedID { syncCanvasSelection() } }
    }
    @Published var activeSheet: EditorSheet?
    @Published var format: Format
    @Published var bpm: Double = 120
    @Published var beatsVisible = true
    @Published var engineDuration: Double = 0
    @Published var bin: [String] = []

    // Transport (see header note).
    @Published var playhead: Double = 0
    @Published var isPlaying = false

    var video: VideoPlayback?
    var layers: LayerFeeder?
    @Published var videoLoaded = false
    @Published var exporting = false        // export owns the engine → live canvas suspended
    @Published var videoDuration: Double?
    @Published var focusNewText = false   // keyboard pops only right after CREATING a title

    @Published var canUndo = false
    @Published var canRedo = false
    private var undoDepth = 0 { didSet { canUndo = undoDepth > 0 } }
    private var redoDepth = 0 { didSet { canRedo = redoDepth > 0 } }

    /// AVFoundation-owned per-source runtime info (true duration, filmstrip).
    private var mediaInfo: [String: MediaInfo] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var lastSnapshot = EngineProjectSnapshot()
    private var textCommitTask: Task<Void, Never>?
    private var paramCommitTask: Task<Void, Never>?
    private var lastEngineSeekSync = Date.distantPast

    // MARK: - Init / hydration

    init(project: Project, engine: EngineStore) {
        self.project = project
        self.engine = engine
        self.format = project.format

        if ProjectStore.exists(project.id) {
            do {
                try ProjectStore.load(engine: engine, id: project.id)
            } catch { /* lastError already published; editor opens empty */ }
        } else {
            engine.send("new_project", ["force": true])
            engine.send("set_format", ["format": project.format.lever])
        }
        refresh()

        // With no media loaded, engine events own the transport readouts.
        engine.$playhead.receive(on: RunLoop.main).sink { [weak self] t in
            guard let self, self.video == nil else { return }
            self.playhead = t
        }.store(in: &cancellables)
        engine.$playing.receive(on: RunLoop.main).sink { [weak self] p in
            guard let self, self.video == nil else { return }
            self.isPlaying = p
        }.store(in: &cancellables)
    }

    /// Re-decode the projection from the engine — after every mutation.
    func refresh(rebuildPlayer: Bool = true) {
        guard let r = try? engine.resultObject("get_project", ["verbose": true]) else { return }
        let snap = EngineProjectSnapshot.decode(r)
        lastSnapshot = snap
        engineDuration = snap.duration
        bpm = snap.bpm
        bin = snap.bin
        if let f = r["format"] as? String { format = Format(engineFormat: f) }
        chapters = snap.markers.map { ChapterMarker($0) }
        tracks = snap.uiTracks(media: { [weak self] in self?.mediaInfo[$0] },
                               resolve: { [weak self] in self?.resolveMedia($0) })
        if let sel = selectedID, locate(sel) == nil { selectedID = nil }
        if let cid = cropEditID, locate(cid) == nil { cancelCrop() }   // crop target vanished

        // Probe any media the projection references that AVFoundation hasn't
        // seen yet (true duration + filmstrip), then re-derive. Keyed by the
        // ENGINE path (what the projection reports), probed at the resolved URL.
        let missing = Set(tracks.flatMap { $0.clips.compactMap { $0.address }}
            .compactMap { lastSnapshot[$0]?.source })
            .subtracting(mediaInfo.keys)
        if !missing.isEmpty { Task { await probeMedia(paths: Array(missing)) } }

        if rebuildPlayer { Task { await rebuildVideo() } }
        syncLiveFX()
    }

    /// Mirror the UI selection into the engine — desktop select_clip semantics:
    /// the canvas selection, i.e. the clip whose transform handles show.
    /// Fire-and-forget (selection is runtime-only, never part of the project).
    private func syncCanvasSelection() {
        if let a = selectedID.flatMap(address) {
            engine.send("select_clip", ["track": a.track, "clip": a.clip])
        } else {
            engine.send("select_clip", ["clip": -1])
        }
    }

    /// Resolve an engine source path to a readable URL. A saved .pms carries
    /// absolute container paths; iOS moves the container between installs, so
    /// stale paths relink into this project's media/ dir by basename.
    private func resolveMedia(_ path: String) -> URL? {
        if FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        let relinked = ProjectStore.mediaDir(project.id)
            .appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent)
        return FileManager.default.fileExists(atPath: relinked.path) ? relinked : nil
    }

    private func probeMedia(paths: [String]) async {
        for path in paths {
            guard let url = resolveMedia(path) else { continue }
            let asset = AVURLAsset(url: url)
            let dur = (try? await asset.load(.duration))?.seconds ?? 0
            guard dur > 0 else { continue }
            // Display size for the canvas bbox aspect-fit (rotation-corrected).
            var size: CGSize?
            if let vt = try? await asset.loadTracks(withMediaType: .video).first,
               let (ns, tf) = try? await vt.load(.naturalSize, .preferredTransform) {
                let s = CGRect(origin: .zero, size: ns).applying(tf).size
                size = CGSize(width: abs(s.width), height: abs(s.height))
            }
            let n = max(1, min(24, Int(dur / 1.5)))
            let strip = await VideoPlayback.filmstrip(for: url, count: n,
                                                      cacheDir: ProjectStore.cacheDir(project.id))
            mediaInfo[path] = MediaInfo(duration: dur, thumbs: strip, size: size)
        }
        tracks = lastSnapshot.uiTracks(media: { [weak self] in self?.mediaInfo[$0] },
                                       resolve: { [weak self] in self?.resolveMedia($0) })
        await rebuildVideo()
    }

    /// One mutating lever: send, adjust the undo depth, refresh the projection.
    /// On rejection the refresh restores the engine's truth (reverts optimism).
    @discardableResult
    private func mutate(_ method: String, _ params: [String: Any],
                        rebuildPlayer: Bool = true) -> [String: Any]? {
        do {
            let r = try engine.result(method, params)
            undoDepth += 1
            redoDepth = 0
            refresh(rebuildPlayer: rebuildPlayer)
            return r as? [String: Any] ?? [:]
        } catch {
            refresh(rebuildPlayer: rebuildPlayer)
            return nil
        }
    }

    // MARK: - Canvas transform gestures (CANVAS_PLAN.md stage 3)
    //
    // One gesture = one engine history entry: begin_batch → throttled
    // set_clip_props → end_batch + a single refresh. During the drag the
    // engine mutates live (the device renderer shows it next frame) and the
    // local projection is patched in place so the overlay tracks the finger
    // without a full re-decode per tick.

    private var canvasGestureActive = false
    private var canvasGestureLastSend = Date.distantPast
    private var canvasGesturePending: (id: String, props: [String: Any])?
    private static let canvasGestureSendInterval = 1.0 / 30.0

    func beginCanvasGesture() {
        guard !canvasGestureActive else { return }
        canvasGestureActive = true
        canvasGesturePending = nil
        engine.send("begin_batch", ["label": "Canvas edit"])
    }

    func updateCanvasGesture(_ id: String, _ props: [String: Any]) {
        guard canvasGestureActive else { return }
        applyCanvasPropsLocally(id, props)
        if Date().timeIntervalSince(canvasGestureLastSend) >= Self.canvasGestureSendInterval {
            sendCanvasProps(id, props)
        } else {
            // coalesce; merged keys keep the newest value
            var merged = canvasGesturePending?.id == id ? canvasGesturePending!.props : [:]
            for (k, v) in props { merged[k] = v }
            canvasGesturePending = (id, merged)
        }
    }

    func endCanvasGesture() {
        guard canvasGestureActive else { return }
        if let p = canvasGesturePending { sendCanvasProps(p.id, p.props) }
        canvasGestureActive = false
        engine.send("end_batch", [:])
        undoDepth += 1
        redoDepth = 0
        refresh(rebuildPlayer: false)   // transforms never touch the AVComposition
        rebuildLayers()                 // text placement lives in the raster → re-submit
    }

    private func sendCanvasProps(_ id: String, _ props: [String: Any]) {
        guard let a = address(id) else { return }
        let ops = props.map { ["track": a.track, "clip": a.clip,
                               "prop": $0.key, "value": $0.value] as [String: Any] }
        engine.send("set_clip_props", ["ops": ops])
        canvasGestureLastSend = Date()
        canvasGesturePending = nil
    }

    /// Patch the in-memory projection so the overlay follows the finger.
    private func applyCanvasPropsLocally(_ id: String, _ props: [String: Any]) {
        guard let r = locate(id), r.kind == .clip else { return }
        var c = tracks[r.track].clips[r.index]
        func d(_ v: Any?) -> Double? {
            (v as? Double) ?? (v as? Int).map(Double.init) ?? (v as? NSNumber)?.doubleValue
        }
        for (k, v) in props {
            switch k {
            case "pos_x":    c.posX = d(v) ?? c.posX
            case "pos_y":    c.posY = d(v) ?? c.posY
            case "scale_x":  c.scaleX = d(v) ?? c.scaleX
            case "scale_y":  c.scaleY = d(v) ?? c.scaleY
            case "rotation": c.rotation = d(v) ?? c.rotation
            case "crop_l":   c.cropL = max(0, min(d(v) ?? 0, 0.95 - c.cropR))
            case "crop_t":   c.cropT = max(0, min(d(v) ?? 0, 0.95 - c.cropB))
            case "crop_r":   c.cropR = max(0, min(d(v) ?? 0, 0.95 - c.cropL))
            case "crop_b":   c.cropB = max(0, min(d(v) ?? 0, 0.95 - c.cropT))
            case "flip_h":   c.flipH = v as? Bool ?? c.flipH
            case "flip_v":   c.flipV = v as? Bool ?? c.flipV
            case "font_size":  c.fontSize = d(v) ?? c.fontSize
            case "sub_pos":    c.subPos = (v as? Int) ?? c.subPos
            case "sub_pos_x":  c.subPosX = d(v) ?? c.subPosX
            case "sub_pos_y":  c.subPosY = d(v) ?? c.subPosY
            case "sub_anchor_h": c.subAnchorH = (v as? Int) ?? c.subAnchorH
            case "sub_wrap_w": c.subWrapW = d(v) ?? c.subWrapW
            default: break
            }
        }
        tracks[r.track].clips[r.index] = c
    }

    // MARK: - Canvas view toggles + one-shot transform actions (stage 6)

    enum SafeZoneMode: CaseIterable { case off, standard, social }
    /// Runtime-only, like desktop show_social_safe — never serialized.
    @Published var safeZones: SafeZoneMode = .off

    func flipClip(_ id: String, horizontal: Bool) {
        guard let r = locate(id), r.kind == .clip, let a = address(id) else { return }
        let c = tracks[r.track].clips[r.index]
        _ = mutate("set_clip_prop", ["track": a.track, "clip": a.clip,
                                     "prop": horizontal ? "flip_h" : "flip_v",
                                     "value": horizontal ? !c.flipH : !c.flipV],
                   rebuildPlayer: false)
    }

    /// Back to the engine defaults: centred, unit scale, no rotation/crop/flips.
    func resetTransform(_ id: String) {
        guard let a = address(id) else { return }
        func op(_ p: String, _ v: Any) -> [String: Any] {
            ["track": a.track, "clip": a.clip, "prop": p, "value": v]
        }
        _ = mutate("set_clip_props", ["ops": [
            op("pos_x", 0.5), op("pos_y", 0.5),
            op("scale_x", 1.0), op("scale_y", 1.0), op("rotation", 0.0),
            op("crop_l", 0.0), op("crop_t", 0.0), op("crop_r", 0.0), op("crop_b", 0.0),
            op("flip_h", false), op("flip_v", false),
        ]], rebuildPlayer: false)
    }

    // MARK: - Crop-edit mode (CANVAS_PLAN.md stage 4)
    //
    // Runtime-only, like desktop crop_edit_track/clip. The whole mode is ONE
    // engine batch: enter → begin_batch, handle drags stream set_clip_props,
    // Apply → end_batch (one history entry), Cancel → abort_batch (engine
    // rolls back to the entry snapshot).

    @Published var cropEditID: String?
    var cropEditClip: Clip? {
        guard let id = cropEditID, let r = locate(id), r.kind == .clip else { return nil }
        return tracks[r.track].clips[r.index]
    }

    func enterCropMode(_ id: String) {
        guard cropEditID == nil, trackKind(ofClip: id) == .video else { return }
        selectedID = id
        cropEditID = id
        canvasGestureActive = true          // reuse the throttled commit path
        canvasGesturePending = nil
        engine.send("begin_batch", ["label": "Crop"])
    }

    func applyCrop() {
        guard cropEditID != nil else { return }
        if let p = canvasGesturePending { sendCanvasProps(p.id, p.props) }
        canvasGestureActive = false
        cropEditID = nil
        engine.send("end_batch", [:])
        undoDepth += 1
        redoDepth = 0
        refresh(rebuildPlayer: false)
    }

    func cancelCrop() {
        guard cropEditID != nil else { return }
        canvasGesturePending = nil
        canvasGestureActive = false
        cropEditID = nil
        engine.send("abort_batch", [:])
        refresh(rebuildPlayer: false)       // restore the engine's rolled-back truth
    }

    /// Flush the coalesced tail of a crop drag (crop mode has no per-drag
    /// end_batch — the mode itself is the batch).
    func flushCanvasGesture() {
        if let p = canvasGesturePending { sendCanvasProps(p.id, p.props) }
    }

    // MARK: - Track scaffolding (created lazily, engine-side)

    /// Canonical lane order, top to bottom: GFX rail, text, video, audio.
    private func canonicalPosition(for kind: TrackKind) -> Int {
        func idx(_ k: TrackKind) -> Int? { tracks.firstIndex { $0.kind == k } }
        switch kind {
        case .fxRail: return 0
        case .lyric:  return (idx(.fxRail).map { $0 + 1 }) ?? 0
        case .shape:  return (idx(.lyric).map { $0 + 1 }) ?? ((idx(.fxRail).map { $0 + 1 }) ?? 0)
        case .video:  return idx(.audio) ?? tracks.count
        case .audio:  return tracks.count
        }
    }
    private func defaultName(for kind: TrackKind) -> String {
        switch kind { case .fxRail: "GFX"; case .video: "V1"; case .lyric: "T1"; case .shape: "S1"; case .audio: "A1" }
    }

    /// Engine track index for a lane kind, creating the track if needed.
    private func ensureTrack(_ kind: TrackKind) -> Int? {
        if let t = tracks.first(where: { $0.kind == kind }), t.engineIndex >= 0 {
            return t.engineIndex
        }
        guard let r = try? engine.resultObject("add_track", [
            "name": defaultName(for: kind), "position": canonicalPosition(for: kind),
        ]) else { return nil }
        refresh(rebuildPlayer: false)
        return r["track"] as? Int
    }

    // MARK: - Import

    func importVideo(_ url: URL) {
        activeSheet = nil
        Task {
            let dur = (try? await AVURLAsset(url: url).load(.duration))?.seconds ?? 0
            guard dur > 0 else {
                engine.lastError = "Could not read that video."
                return
            }
            let media = ProjectStore.importMedia(url, into: project.id)
            // GFX rail FIRST — it inserts at engine position 0 and would shift
            // an already-captured video track index.
            _ = ensureTrack(.fxRail)
            guard let ti = ensureTrack(.video) else { return }
            // Append after the last clip on the video track.
            let startAt = tracks.first { $0.engineIndex == ti }?.clips.map(\.end).max() ?? 0
            let r = mutate("add_clip", [
                "track": ti, "type": "video",
                "start": startAt, "end": startAt + dur, "text": media.path,
            ])
            if let ci = r?["clip"] as? Int {
                selectedID = EngineClipAddress(track: ti, clip: ci).idString
            }
            videoLoaded = true
        }
    }

    // MARK: - Undo / redo (the engine's history)

    func undo() {
        // A pending debounced commit would re-apply the value being undone.
        textCommitTask?.cancel(); paramCommitTask?.cancel()
        guard (try? engine.result("undo")) != nil else { return }
        undoDepth -= 1; redoDepth += 1
        selectedID = nil
        refresh()
    }
    func redo() {
        textCommitTask?.cancel(); paramCommitTask?.cancel()
        guard (try? engine.result("redo")) != nil else { return }
        redoDepth -= 1; undoDepth += 1
        selectedID = nil
        refresh()
    }

    // MARK: - Address resolution

    enum ItemKind { case clip, brick }
    /// The address of a timeline item in the CURRENT projection. Resolve on
    /// demand — never store across a mutation (indices shift).
    struct ItemRef { let id: String; let track: Int; let index: Int; let kind: ItemKind }

    func locate(_ id: String) -> ItemRef? {
        for (ti, tr) in tracks.enumerated() {
            if let ci = tr.clips.firstIndex(where: { $0.id == id })  { return ItemRef(id: id, track: ti, index: ci, kind: .clip) }
            if let bi = tr.bricks.firstIndex(where: { $0.id == id }) { return ItemRef(id: id, track: ti, index: bi, kind: .brick) }
        }
        return nil
    }
    var selectedRef: ItemRef? { selectedID.flatMap(locate) }

    /// Engine address for a UI item id.
    private func address(_ id: String) -> EngineClipAddress? {
        guard let r = locate(id) else { return nil }
        return r.kind == .clip ? tracks[r.track].clips[r.index].address
                               : tracks[r.track].bricks[r.index].address
    }

    private var videoTrackIndex: Int? { tracks.firstIndex { $0.kind == .video } }
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

    /// Title/lyric clips (engine scene layers; also export raster sources).
    var titleClips: [Clip] { tracks.filter { $0.kind == .lyric }.flatMap(\.clips) }

    /// The PRIMARY video track: the bottom-most video lane (deepest layer) —
    /// its clips play through the main AVPlayer (the transport master clock).
    /// Other video tracks are overlay layers fed by LayerFeeder.
    var primaryVideoEngineTrack: Int? {
        tracks.last { $0.kind == .video }?.engineIndex
    }

    private func segments(fromEngineTrack et: Int?) -> [VideoPlayback.Segment] {
        guard let et else { return [] }
        return (tracks.first { $0.engineIndex == et }?.clips ?? []).compactMap { c in
            guard let url = c.sourceURL,
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return VideoPlayback.Segment(url: url, start: c.start, sourceStart: c.sourceStart,
                                         duration: c.duration, speed: c.speed,
                                         fadeIn: c.fadeIn, fadeOut: c.fadeOut)
        }
    }

    /// Primary-track clips as playback/export segments.
    var videoSegments: [VideoPlayback.Segment] {
        segments(fromEngineTrack: primaryVideoEngineTrack)
    }
    /// Overlay video-track clips (video-only layers; audio is a v1 gap).
    var overlaySegmentsExist: Bool {
        tracks.contains { $0.kind == .video && $0.engineIndex != primaryVideoEngineTrack && !$0.clips.isEmpty }
    }
    /// Audio-track clips — sound only, mixed into the AVComposition.
    var audioOnlySegments: [VideoPlayback.Segment] {
        tracks.filter { $0.kind == .audio }.flatMap(\.clips).compactMap { c in
            guard let url = c.sourceURL,
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return VideoPlayback.Segment(url: url, start: c.start, sourceStart: c.sourceStart,
                                         duration: c.duration, speed: c.speed)
        }
    }

    /// Rebuild the player timeline from the projection: the main AVPlayer
    /// carries the PRIMARY video track (+ all audio); every other visual layer
    /// (overlay video, text) is an engine scene layer fed by LayerFeeder.
    /// Text is NOT baked into the composition — the engine composites it at
    /// its track's z-order, exactly like the desktop.
    func rebuildVideo(seekTo: Double? = nil) async {
        rebuildLayers()
        let segs = videoSegments
        if segs.isEmpty {
            video?.stop(); video = nil
            videoLoaded = false; videoDuration = nil
            if isPlaying { isPlaying = false; engine.send("pause") }
            return
        }
        if video == nil {
            let v = VideoPlayback(engine: engine)
            v.onTick = { [weak self] time, playing in self?.playerTick(time, playing) }
            video = v
        }
        wireBaseFrameSink()
        await video?.load(segments: segs, audioOnly: audioOnlySegments, seekTo: seekTo, size: CGSize(width: format.pixelSize.w, height: format.pixelSize.h))
        videoDuration = video?.duration
        videoLoaded = true
    }

    /// Route the main player's decoded frames to the engine as the PRIMARY
    /// track's layer, addressed by whichever clip covers the frame time.
    private func wireBaseFrameSink() {
        video?.frameSink = { [weak self] pb, t in
            guard let self else { return }
            guard let et = self.primaryVideoEngineTrack,
                  let tr = self.tracks.first(where: { $0.engineIndex == et }),
                  let c = tr.clips.first(where: { t >= $0.start && t < $0.end }) ?? tr.clips.last,
                  let a = c.address else {
                self.engine.submitCameraFrame(pb, rotation: 0, hostTime: t)   // legacy fallback
                return
            }
            self.engine.submitLayerFrame(track: a.track, clip: a.clip, pb, hostTime: t)
        }
    }

    /// Reconfigure the layer feeder from the current projection.
    private func rebuildLayers() {
        if layers == nil { layers = LayerFeeder(engine: engine) }
        layers?.rebuild(tracks: tracks, snapshot: lastSnapshot,
                        primaryEngineTrack: primaryVideoEngineTrack ?? -1,
                        excludingText: selectedLyricClip?.address,
                        canvas: CGSize(width: format.pixelSize.w, height: format.pixelSize.h),
                        resolveMedia: { [weak self] in self?.resolveMedia($0) })
        layers?.transport(playhead: playhead, playing: isPlaying)
    }

    /// AVPlayer clock → transport readout + throttled engine reconciliation +
    /// overlay-layer sync.
    private func playerTick(_ time: Double, _ playing: Bool) {
        playhead = time
        isPlaying = playing
        layers?.transport(playhead: time, playing: playing)
        if playing, Date().timeIntervalSince(lastEngineSeekSync) > 0.2 {
            lastEngineSeekSync = Date()
            engine.send("seek", ["time": time])
        }
    }

    // MARK: - Live drag optimism (engine lever lands on gesture end)

    private let snapRadius = 0.17   // ≈ 8px @ PPS 46 (desktop SNAP_PX / zoom)

    func beginEdit() { }            // gesture latches its own origin

    /// Trim released → one trim_clip (engine derives in_point from the start delta).
    func endEdit(_ id: String) {
        guard let r = locate(id) else { return }
        // A coupled brick tracks its host clip's span (fx_coupling_tick re-snaps
        // it every engine tick) — a trim would silently revert. Say so instead.
        if r.kind == .brick, tracks[r.track].bricks[r.index].coupled {
            engine.lastError = "This FX brick is welded to its clip and follows its span — Decouple it to resize freely."
            refresh(rebuildPlayer: false)
            return
        }
        let (start, end): (Double, Double) = r.kind == .clip
            ? (tracks[r.track].clips[r.index].start, tracks[r.track].clips[r.index].end)
            : (tracks[r.track].bricks[r.index].start, tracks[r.track].bricks[r.index].end)
        guard let a = address(id) else { return }
        _ = mutate("trim_clip", ["track": a.track, "clip": a.clip,
                                 "start": start, "end": end],
                   rebuildPlayer: r.kind == .clip)
    }

    /// Lines a dragged edge snaps to: playhead, 0, every OTHER clip's AND brick's edges.
    private func snapCandidates(excluding id: String) -> [Double] {
        var c: [Double] = [playhead, 0]
        for tr in tracks {
            for cl in tr.clips  where cl.id != id { c.append(cl.start); c.append(cl.end) }
            for b  in tr.bricks where b.id  != id { c.append(b.start);  c.append(b.end) }
        }
        return c
    }
    func snapEdge(_ t: Double, excluding id: String) -> Double {
        var best = t, dt = snapRadius
        for c in snapCandidates(excluding: id) where abs(c - t) < dt { dt = abs(c - t); best = c }
        return best
    }
    func snapStart(_ t: Double, excluding id: String, duration dur: Double) -> Double {
        var best = t, dt = snapRadius
        for c in snapCandidates(excluding: id) {
            if abs(c - t) < dt         { dt = abs(c - t);         best = c }
            if abs(c - (t + dur)) < dt { dt = abs(c - (t + dur)); best = c - dur }
        }
        return best
    }
    /// Walls: an edge can't cross a same-track neighbor.
    func trimWalls(excluding id: String, origStart: Double, origEnd: Double) -> (floor: Double, ceil: Double) {
        guard let ti = trackIndex(ofClip: id) else { return (0, .greatestFiniteMagnitude) }
        var floor = 0.0, ceil = Double.greatestFiniteMagnitude
        for oc in tracks[ti].clips where oc.id != id {
            if oc.end   <= origStart + 0.001 { floor = max(floor, oc.end) }
            if oc.start >= origEnd   - 0.001 { ceil  = min(ceil, oc.start) }
        }
        return (floor, ceil)
    }

    /// Live setter during a trim drag — local cache only.
    func setTrim(_ id: String, start: Double, sourceStart: Double, duration: Double) {
        guard let ti = trackIndex(ofClip: id), let ci = tracks[ti].clips.firstIndex(where: { $0.id == id }) else { return }
        tracks[ti].clips[ci].start = max(0, start)
        tracks[ti].clips[ci].sourceStart = max(0, sourceStart)
        tracks[ti].clips[ci].duration = max(0.3, duration)
    }

    // Brick drag — live-local; engine lever on release.
    func setBrickStart(_ id: String, _ start: Double) {
        guard let r = locate(id), r.kind == .brick else { return }
        tracks[r.track].bricks[r.index].start = max(0, start)
    }
    func setBrickTrim(_ id: String, start: Double, duration: Double) {
        guard let r = locate(id), r.kind == .brick else { return }
        tracks[r.track].bricks[r.index].start = max(0, start)
        tracks[r.track].bricks[r.index].duration = max(0.15, duration)
    }
    func brickConflicts(_ id: String) -> Bool {
        guard let r = locate(id), r.kind == .brick else { return false }
        let b = tracks[r.track].bricks[r.index]
        return tracks[r.track].bricks.contains { $0.id != id && b.start < $0.end && b.end > $0.start }
    }
    func brickTrimWalls(_ id: String, origStart: Double, origEnd: Double) -> (floor: Double, ceil: Double) {
        guard let r = locate(id), r.kind == .brick else { return (0, .greatestFiniteMagnitude) }
        var floor = 0.0, ceil = Double.greatestFiniteMagnitude
        for ob in tracks[r.track].bricks where ob.id != id {
            if ob.end   <= origStart + 0.001 { floor = max(floor, ob.end) }
            if ob.start >= origEnd   - 0.001 { ceil  = min(ceil, ob.start) }
        }
        return (floor, ceil)
    }
    func endBrickMove(_ id: String, originStart: Double) {
        if let r = locate(id), r.kind == .brick, tracks[r.track].bricks[r.index].coupled {
            engine.lastError = "This FX brick is welded to its clip and follows it — Decouple it to move it freely."
            refresh(rebuildPlayer: false)
            return
        }
        if brickConflicts(id) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { setBrickStart(id, originStart) }
            refresh(rebuildPlayer: false)   // restore engine truth
            return
        }
        guard let r = locate(id), r.kind == .brick, let a = address(id) else { return }
        _ = mutate("move_clip", ["track": a.track, "clip": a.clip,
                                 "start": tracks[r.track].bricks[r.index].start],
                   rebuildPlayer: false)
    }

    // Body move — free set-start live, engine move_clip on release.
    func setClipStart(_ id: String, _ newStart: Double) {
        guard let ti = trackIndex(ofClip: id), let ci = tracks[ti].clips.firstIndex(where: { $0.id == id }) else { return }
        tracks[ti].clips[ci].start = max(0, newStart)
    }
    func clipConflicts(_ id: String) -> Bool {
        guard let ti = trackIndex(ofClip: id), let c = tracks[ti].clips.first(where: { $0.id == id }) else { return false }
        return tracks[ti].clips.contains { $0.id != id && c.start < $0.end && c.end > $0.start }
    }
    func endMove(_ id: String, originStart: Double) {
        if clipConflicts(id) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { setClipStart(id, originStart) }
            refresh()
            return
        }
        guard let ti = trackIndex(ofClip: id),
              let c = tracks[ti].clips.first(where: { $0.id == id }),
              let a = address(id) else { return }
        _ = mutate("move_clip", ["track": a.track, "clip": a.clip, "start": c.start],
                   rebuildPlayer: trackKind(ofClip: id) == .video)
    }

    // MARK: - Fades (live value; engine commit on release)

    func setFade(_ id: String, fadeIn: Double? = nil, fadeOut: Double? = nil) {
        guard let ti = trackIndex(ofClip: id), let ci = tracks[ti].clips.firstIndex(where: { $0.id == id }) else { return }
        if let fadeIn  { tracks[ti].clips[ci].fadeIn  = max(0, fadeIn) }
        if let fadeOut { tracks[ti].clips[ci].fadeOut = max(0, fadeOut) }
    }
    func commitFade() {
        guard let id = selectedID, let r = locate(id), r.kind == .clip,
              let a = address(id) else { return }
        let c = tracks[r.track].clips[r.index]
        _ = mutate("set_clip_props", ["ops": [
            ["track": a.track, "clip": a.clip, "prop": "fade_in",  "value": c.fadeIn],
            ["track": a.track, "clip": a.clip, "prop": "fade_out", "value": c.fadeOut],
        ]])
    }

    // MARK: - Split / delete

    /// Split the SELECTED item (clip or FX brick) at the playhead.
    func splitAtPlayhead() {
        guard let id = selectedID, let a = address(id) else { return }
        let r = mutate("split_clip", ["track": a.track, "clip": a.clip, "time": playhead])
        if let right = r?["right_clip"] as? Int {
            selectedID = EngineClipAddress(track: a.track, clip: right).idString
        }
    }

    /// Universal delete — any clip or brick, engine-addressed.
    func deleteSelected(_ id: String? = nil) {
        guard let rid = id ?? selectedID, let a = address(rid) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            _ = mutate("delete_clip", ["track": a.track, "clip": a.clip])
            if selectedID == rid { selectedID = nil }
        }
    }
    func deleteSelectedClip() { deleteSelected() }
    func deleteClipAnywhere(_ id: String) { deleteSelected(id) }

    // MARK: - Text / lyric clips

    func activeLyrics(at t: Double) -> [Clip] {
        tracks.first { $0.kind == .lyric }?.clips.filter { t >= $0.start && t < $0.end } ?? []
    }
    var selectedLyricClip: Clip? {
        tracks.first { $0.kind == .lyric }?.clips.first { $0.id == selectedID }
    }

    /// Add a text clip at the playhead (creates the text track if needed) + select it.
    func addTextClip() {
        activeSheet = nil
        guard let ti = ensureTrack(.lyric) else { return }
        let r = mutate("add_clip", ["track": ti, "type": "text",
                                    "start": playhead, "end": playhead + 3,
                                    "text": "YOUR TEXT"],
                       rebuildPlayer: false)
        if let ci = r?["clip"] as? Int {
            selectedID = EngineClipAddress(track: ti, clip: ci).idString
            focusNewText = true
        }
    }

    /// Engine clip type / animation style at an address (for sheets that need
    /// engine vocabulary the UI structs don't carry).
    func engineClipType(_ a: EngineClipAddress) -> String? { lastSnapshot[a]?.type }
    func engineClipStyle(_ a: EngineClipAddress) -> String? { lastSnapshot[a]?.clipStyle }

    /// Set a text clip's animation style (engine anim vocabulary: fade/glitch/…).
    func setClipStyle(_ id: String, style: String) {
        guard let a = address(id) else { return }
        _ = mutate("set_clip_prop", ["track": a.track, "clip": a.clip,
                                     "prop": "clip_style", "value": style],
                   rebuildPlayer: false)
    }

    // MARK: - Shape clips

    var selectedShapeClip: Clip? {
        tracks.first { $0.kind == .shape }?.clips.first { $0.id == selectedID }
    }

    /// Add a preset shape clip at the playhead (creates the shape track if
    /// needed) + select it. Returns the new clip id so the caller can open the
    /// path editor if desired.
    @discardableResult
    func addShapeClip(preset: String, params: [Double] = []) -> String? {
        guard let ti = ensureTrack(.shape) else { return nil }
        let start = playhead
        let r = mutate("add_shape", ["track": ti, "start": start,
                                     "end": start + 3, "preset": preset,
                                     "params": params] as [String: Any],
                       rebuildPlayer: false)
        if let ci = r?["clip"] as? Int {
            let id = EngineClipAddress(track: ti, clip: ci).idString
            selectedID = id
            // Tag the projection's preset label locally (engine doesn't persist
            // it) so the timeline shows "star" not "Shape".
            if let pair = locate(id),
               case .clip = pair.kind {
                tracks[pair.track].clips[pair.index].shapePreset = preset
                tracks[pair.track].clips[pair.index].label = preset.capitalized
            }
            return id
        }
        return nil
    }

    /// Replace a shape clip's base path with a freehand/custom path.
    func setShapePath(_ id: String, points: [[String: Any]], closed: Bool) {
        guard let a = address(id) else { return }
        _ = mutate("set_shape_path", ["track": a.track, "clip": a.clip,
                                      "points": points, "closed": closed] as [String: Any],
                   rebuildPlayer: false)
        if let pair = locate(id), case .clip = pair.kind {
            tracks[pair.track].clips[pair.index].shapePreset = "Freehand"
            tracks[pair.track].clips[pair.index].label = "Freehand"
        }
    }

    /// One style field at a time → set_shape_style. `value` is Any (bool/double/[double]).
    func setShapeStyle(_ id: String, key: String, value: Any) {
        guard let a = address(id) else { return }
        _ = mutate("set_shape_style", ["track": a.track, "clip": a.clip, key: value] as [String: Any],
                   rebuildPlayer: false)
    }

    /// Replace morph keyframes (empty keys clears).
    func setShapeKeyframes(_ id: String, keys: [[String: Any]]) {
        guard let a = address(id) else { return }
        _ = mutate("set_shape_keyframes", ["track": a.track, "clip": a.clip,
                                           "keys": keys] as [String: Any],
                   rebuildPlayer: false)
    }

    /// Add a morph key capturing the current base path at the playhead.
    func addShapeMorphKey(_ id: String) {
        guard let a = address(id), let snap = lastSnapshot[a],
              let path = snap.shapePath else { return }
        let t = max(0, playhead - snap.start)
        var keys: [[String: Any]] = (snap.shapeKeys.map { k in
            ["t": k.time, "points": k.path.points.map { ["x": $0.x, "y": $0.y, "w": $0.width] },
             "closed": k.path.closed, "interp": k.interp] as [String: Any]
        })
        keys.removeAll { abs((($0["t"] as? Double) ?? -1) - t) < 1e-3 }
        keys.append(["t": t,
                     "points": path.points.map { ["x": $0.x, "y": $0.y, "w": $0.width] },
                     "closed": path.closed, "interp": "ease_both"] as [String: Any])
        setShapeKeyframes(id, keys: keys)
    }

    /// Remove a morph key by index.
    func removeShapeMorphKey(_ id: String, index: Int) {
        guard let a = address(id), let snap = lastSnapshot[a] else { return }
        guard snap.shapeKeys.indices.contains(index) else { return }
        let keys: [[String: Any]] = snap.shapeKeys.enumerated().compactMap { i, k in
            i == index ? nil
            : ["t": k.time, "points": k.path.points.map { ["x": $0.x, "y": $0.y, "w": $0.width] },
               "closed": k.path.closed, "interp": k.interp] as [String: Any]
        }
        setShapeKeyframes(id, keys: keys)
    }
    /// Add a scalar keyframe (shape_stroke_length / shape_stroke_width_mul) at
    /// the playhead. Read-modify-write via the projection's full key list so
    /// existing keys are preserved (the engine replaces the whole track).
    func addShapeScalarKey(_ id: String, prop: String, value: Double) {
        guard let a = address(id), let snap = lastSnapshot[a] else { return }
        let t = max(0, playhead - snap.start)
        var keys = snap.shapeScalarKeys[prop] ?? []
        keys.removeAll { abs($0.time - t) < 1e-3 }
        keys.append(ScalarKeyframe(time: t, value: value, interp: "ease_both"))
        keys.sort { $0.time < $1.time }
        let payload: [[String: Any]] = keys.map { ["t": $0.time, "v": $0.value, "interp": $0.interp] }
        _ = mutate("set_clip_keyframes", ["track": a.track, "clip": a.clip,
                                          "prop": prop, "keys": payload] as [String: Any],
                   rebuildPlayer: false)
    }

    /// Set a scalar shape prop's value via its keyframe track (the engine
    /// exposes shape_stroke_length / shape_stroke_width_mul only through
    /// set_clip_keyframes — there's no set_clip_prop for them). With no
    /// existing keys, a single key at t=0 acts as the constant base value;
    /// with keys, the one nearest the playhead is updated.
    func setShapeScalar(_ id: String, prop: String, value: Double) {
        guard let a = address(id), let snap = lastSnapshot[a] else { return }
        let tLocal = max(0, playhead - snap.start)
        var keys = snap.shapeScalarKeys[prop] ?? []
        if keys.isEmpty {
            keys = [ScalarKeyframe(time: 0, value: value, interp: "ease_both")]
        } else if let ni = keys.enumerated().min(by: { abs($0.element.time - tLocal) < abs($1.element.time - tLocal) })?.offset,
                  abs(keys[ni].time - tLocal) < 1e-3 {
            keys[ni].value = value
        } else {
            keys.append(ScalarKeyframe(time: tLocal, value: value, interp: "ease_both"))
            keys.sort { $0.time < $1.time }
        }
        let payload: [[String: Any]] = keys.map { ["t": $0.time, "v": $0.value, "interp": $0.interp] }
        _ = mutate("set_clip_keyframes", ["track": a.track, "clip": a.clip,
                                          "prop": prop, "keys": payload] as [String: Any],
                   rebuildPlayer: false)
    }

    /// Remove a scalar keyframe by index.
    func removeShapeScalarKey(_ id: String, prop: String, index: Int) {
        guard let a = address(id), let snap = lastSnapshot[a] else { return }
        var keys = snap.shapeScalarKeys[prop] ?? []
        guard keys.indices.contains(index) else { return }
        keys.remove(at: index)
        let payload: [[String: Any]] = keys.map { ["t": $0.time, "v": $0.value, "interp": $0.interp] }
        _ = mutate("set_clip_keyframes", ["track": a.track, "clip": a.clip,
                                          "prop": prop, "keys": payload] as [String: Any],
                   rebuildPlayer: false)
    }

    /// Clear all keyframes for a scalar shape prop.
    func clearShapeScalarKeys(_ id: String, prop: String) {
        guard let a = address(id) else { return }
        _ = mutate("set_clip_keyframes", ["track": a.track, "clip": a.clip,
                                          "prop": prop, "keys": []] as [String: Any],
                   rebuildPlayer: false)
    }

    /// Fetch the engine's evaluated path at the playhead (for the path editor).
    func engineShapePath(_ id: String) -> ShapePathProj? {
        guard let a = address(id) else { return nil }
        guard let r = try? engine.resultObject("get_shape_path",
                                                ["track": a.track, "clip": a.clip,
                                                 "t": playhead] as [String: Any]) else { return nil }
        if (r["error"] as? String) != nil { return nil }
        let pts = (r["points"] as? [[String: Any]] ?? []).map { p in
            ShapePoint(x: (p["x"] as? Double) ?? 0.5, y: (p["y"] as? Double) ?? 0.5,
                       width: (p["w"] as? Double) ?? 0.008)
        }
        return ShapePathProj(points: pts, closed: (r["closed"] as? Bool) ?? false)
    }

    /// Place a project-bin item on the timeline at the playhead (video/audio by
    /// extension), creating the destination track if needed.
    func placeBinItem(_ path: String) {
        let isAudio = ["wav", "mp3", "m4a", "aac", "flac"]
            .contains(URL(fileURLWithPath: path).pathExtension.lowercased())
        Task {
            let dur = (try? await AVURLAsset(url: URL(fileURLWithPath: path)).load(.duration))?.seconds ?? 0
            guard dur > 0 else {
                engine.lastError = "Could not read \(URL(fileURLWithPath: path).lastPathComponent)."
                return
            }
            guard let ti = ensureTrack(isAudio ? .audio : .video) else { return }
            let start = firstFreeStart(onTrack: tracks.firstIndex { $0.engineIndex == ti } ?? 0,
                                       preferred: playhead, duration: dur)
            let r = mutate("add_clip", ["track": ti, "type": isAudio ? "audio" : "video",
                                        "start": start, "end": start + dur, "text": path])
            if let ci = r?["clip"] as? Int {
                selectedID = EngineClipAddress(track: ti, clip: ci).idString
            }
            activeSheet = nil
        }
    }

    /// Land a recorded take at the playhead and weld the record-time look over
    /// its span as a coupled Multi-FX brick — the take file stays raw (filters
    /// are non-destructive; export bakes them), the look stays editable.
    func placeRecordedTake(_ path: String, look entries: [[String: Any]]) {
        Task {
            let dur = (try? await AVURLAsset(url: URL(fileURLWithPath: path)).load(.duration))?.seconds ?? 0
            guard dur > 0 else {
                engine.lastError = "Take failed to read back."
                return
            }
            guard let ti = ensureTrack(.video) else { return }
            let start = firstFreeStart(onTrack: tracks.firstIndex { $0.engineIndex == ti } ?? 0,
                                       preferred: playhead, duration: dur)
            guard let r = mutate("add_clip", ["track": ti, "type": "video",
                                              "start": start, "end": start + dur, "text": path]),
                  let ci = r["clip"] as? Int else { return }
            if !entries.isEmpty {
                // Overlapping the host clip's span couples the brick to it
                // (same contract as FXSheet's Glass placement).
                _ = mutate("add_multifx_brick", ["track": ti, "start": start,
                                                 "end": start + dur, "effects": entries],
                           rebuildPlayer: false)
            }
            selectedID = EngineClipAddress(track: ti, clip: ci).idString
        }
    }

    /// Place multiple recorded segments contiguously as one atomic undo entry.
    @discardableResult
    func placeRecordedTakes(_ segments: [(path: String, duration: Double)]) -> Bool {
        guard !segments.isEmpty else { return false }
        guard segments.allSatisfy({ $0.duration > 0 }) else {
            engine.lastError = "Recorded segments must have positive durations."
            return false
        }
        guard let ti = ensureTrack(.video) else {
            engine.lastError = "Could not create the video track."
            return false
        }
        let totalDuration = segments.reduce(0) { $0 + $1.duration }
        guard let localIdx = tracks.firstIndex(where: { $0.engineIndex == ti }) else {
            engine.lastError = "Could not locate the video track."
            return false
        }
        let start = firstFreeStart(onTrack: localIdx, preferred: playhead, duration: totalDuration)

        guard (try? engine.result("begin_batch", ["label": "Recorded segments"])) != nil else {
            engine.lastError = "Could not begin recording placement."
            return false
        }
        var cursor = start
        var lastClip: Int?
        for segment in segments {
            guard let r = try? engine.resultObject("add_clip", [
                "track": ti, "type": "video",
                "start": cursor, "end": cursor + segment.duration,
                "text": segment.path,
            ]), let ci = r["clip"] as? Int else {
                engine.send("abort_batch", [:])
                engine.lastError = "Could not place all recorded segments."
                refresh()
                return false
            }
            lastClip = ci
            cursor += segment.duration
        }
        engine.send("end_batch", [:])
        undoDepth += 1
        redoDepth = 0
        refresh()
        if let lastClip = lastClip {
            selectedID = EngineClipAddress(track: ti, clip: lastClip).idString
        }
        return true
    }

    /// Live typing updates the cache; the engine commit is debounced so a word
    /// is one history step, not one per keystroke.
    func setClipText(_ id: String, _ text: String) {
        guard let r = locate(id), r.kind == .clip else { return }
        tracks[r.track].clips[r.index].label = text
        guard let a = address(id) else { return }
        textCommitTask?.cancel()
        textCommitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.commitText(a, text)
        }
    }
    private func commitText(_ a: EngineClipAddress, _ text: String) {
        // rebuildPlayer: titles bake into the composition, so the committed
        // text must reach the player (the edited clip is overlay-drawn until
        // deselected, so this only matters for preview==export fidelity).
        _ = mutate("set_clip_prop", ["track": a.track, "clip": a.clip,
                                     "prop": "text", "value": text])
    }

    // MARK: - Selection routing
    enum SelectionBar { case none; case clip(Clip); case lyric(Clip); case shape(Clip); case brick(Brick) }
    var selectedBar: SelectionBar {
        guard let r = selectedRef else { return .none }
        switch r.kind {
        case .clip:  let c = tracks[r.track].clips[r.index]
                     switch tracks[r.track].kind {
                     case .lyric: return .lyric(c)
                     case .shape: return .shape(c)
                     default:     return .clip(c)
                     }
        case .brick: return .brick(tracks[r.track].bricks[r.index])
        }
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

    // MARK: - Copy / paste / duplicate (recreated through engine levers)

    struct ClipboardItem {
        enum Payload { case clip(Clip, type: String); case brick(Brick) }
        let payload: Payload
        let trackKind: TrackKind
    }
    @Published var clipboard: ClipboardItem?

    private func engineType(of c: Clip, on kind: TrackKind) -> String {
        guard let a = c.address, let snap = lastSnapshot[a] else {
            switch kind { case .video: return "video"; case .audio: return "audio"; case .shape: return "shape"; default: return "text" }
        }
        return snap.type
    }

    func copyItem(_ id: String? = nil) {
        guard let r = (id ?? selectedID).flatMap(locate) else { return }
        let kind = tracks[r.track].kind
        clipboard = r.kind == .clip
            ? ClipboardItem(payload: .clip(tracks[r.track].clips[r.index],
                                           type: engineType(of: tracks[r.track].clips[r.index], on: kind)),
                            trackKind: kind)
            : ClipboardItem(payload: .brick(tracks[r.track].bricks[r.index]), trackKind: kind)
    }
    func cutItem(_ id: String? = nil) {
        guard let r = (id ?? selectedID).flatMap(locate) else { return }
        copyItem(r.id); deleteSelected(r.id)
    }
    /// Paste lands at the PLAYHEAD (NLE convention).
    func pasteItem() {
        guard let cb = clipboard else { return }
        insertCopy(cb, at: playhead)
    }
    /// Duplicate lands right AFTER the original.
    func duplicateItem(_ id: String? = nil) {
        guard let r = (id ?? selectedID).flatMap(locate) else { return }
        copyItem(r.id)
        guard let cb = clipboard else { return }
        let end = r.kind == .clip ? tracks[r.track].clips[r.index].end
                                  : tracks[r.track].bricks[r.index].end
        insertCopy(cb, at: end)
    }

    private func firstFreeStart(onTrack ti: Int, preferred: Double, duration: Double) -> Double {
        var start = max(0, preferred), moved = true
        while moved { moved = false
            for o in tracks[ti].clips where start < o.end && start + duration > o.start { start = o.end; moved = true }
        }
        return start
    }

    private func insertCopy(_ cb: ClipboardItem, at t: Double) {
        guard let ti = tracks.firstIndex(where: { $0.kind == cb.trackKind }),
              tracks[ti].engineIndex >= 0 else { return }
        let et = tracks[ti].engineIndex
        switch cb.payload {
        case .clip(let c, let type):
            let start = firstFreeStart(onTrack: ti, preferred: t, duration: c.duration)
            var params: [String: Any] = ["track": et, "type": type,
                                         "start": start, "end": start + c.duration]
            params["text"] = c.sourceURL?.path ?? c.label
            // in_point is only reachable through the trim contract (a start
            // delta scales into source seconds) — so a trimmed copy is created
            // covering the pre-roll span, then trimmed forward to `start`.
            let pre = c.sourceStart > 0.01 ? start - c.sourceStart / max(0.01, c.speed) : start
            let usePreRoll = pre >= 0 && pre < start
            if usePreRoll { params["start"] = pre }
            let r = mutate("add_clip", params)
            if let ci = r?["clip"] as? Int {
                if usePreRoll {
                    _ = mutate("trim_clip", ["track": et, "clip": ci,
                                             "start": start, "end": start + c.duration])
                }
                selectedID = EngineClipAddress(track: et, clip: ci).idString
            }
        case .brick(let b):
            placeBrickCopy(b, onEngineTrack: et, at: t)
        }
    }

    private func placeBrickCopy(_ b: Brick, onEngineTrack et: Int, at t: Double) {
        let r: [String: Any]?
        switch b.kind {
        case .multiFX:
            r = mutate("add_multifx_brick", [
                "track": et, "start": t, "end": t + b.duration,
                "effects": b.chainEntries(),
            ], rebuildPlayer: false)
        case .audioFX:
            r = mutate("add_audio_multifx_brick", [
                "track": et, "start": t, "end": t + b.duration,
                "effects": b.chainEntries(),
            ], rebuildPlayer: false)
        case .bodyFX:
            r = mutate("add_clip", ["track": et, "type": "body_fx",
                                    "start": t, "end": t + b.duration], rebuildPlayer: false)
            if let ci = r?["clip"] as? Int, let bodyType = b.bodyFXType {
                _ = mutate("set_clip_prop", ["track": et, "clip": ci,
                                             "prop": "body_fx_type", "value": bodyType],
                           rebuildPlayer: false)
            }
        case .glassFX, .globalFX:
            r = mutate("add_effect_brick", [
                "track": et, "fx_type": b.chain.first ?? "grade",
                "start": t, "end": t + b.duration, "params": b.params,
            ], rebuildPlayer: false)
        }
        if let ci = r?["clip"] as? Int {
            selectedID = EngineClipAddress(track: et, clip: ci).idString
        }
    }

    // MARK: - Transport (engine owns state; AVPlayer is the media clock)

    func togglePlay() {
        isPlaying.toggle()
        engine.send(isPlaying ? "play" : "pause")
        if let v = video { isPlaying ? v.play() : v.pause() }
        layers?.transport(playhead: playhead, playing: isPlaying)
        if !isPlaying { engine.send("seek", ["time": playhead]) }   // land the exact pause point
    }
    func seek(_ t: Double) {
        let v = min(max(t, 0), duration)
        playhead = v
        engine.send("seek", ["time": v])
        video?.seek(v)
        layers?.transport(playhead: v, playing: isPlaying)
    }

    // MARK: - Track reordering (track order IS canvas z-order)

    /// Move a lane up/down one slot (UI index space == engine index space).
    func moveTrack(engineIndex: Int, delta: Int) {
        let to = engineIndex + delta
        guard engineIndex >= 0, to >= 0, to < tracks.count else { return }
        _ = mutate("move_track", ["from": engineIndex, "to": to])
    }
    /// Pause playback when the user grabs the timeline to scrub.
    func pauseForScrub() {
        if isPlaying {
            video?.pause(); isPlaying = false
            engine.send("pause")
        }
    }

    // MARK: - Body FX (defs live in the engine; see list_body_fx)

    @Published var bodyEffects: [BodyFXDef] = []

    func loadBodyEffects() {
        guard bodyEffects.isEmpty,
              let r = try? engine.resultObject("list_body_fx"),
              let arr = r["effects"] as? [[String: Any]] else { return }
        bodyEffects = arr.compactMap(BodyFXDef.decode)
    }
    func bodyDef(named name: String?) -> BodyFXDef? {
        guard let name else { return nil }
        return bodyEffects.first { $0.name == name }
    }

    /// Place a body-FX brick: one body_fx clip + typed props (the doc contract —
    /// there is no add_body_fx_brick handler).
    @discardableResult
    func placeBodyEffect(_ def: BodyFXDef, at t: Double) -> Bool {
        guard let ti = tracks.firstIndex(where: { $0.kind == .video }),
              tracks[ti].engineIndex >= 0 else { return false }
        let et = tracks[ti].engineIndex
        guard let r = mutate("add_clip", ["track": et, "type": "body_fx",
                                          "start": t, "end": t + 2], rebuildPlayer: false),
              let ci = r["clip"] as? Int else { return false }
        _ = mutate("set_clip_props", ["ops": [
            ["track": et, "clip": ci, "prop": "body_fx_type", "value": def.name],
            ["track": et, "clip": ci, "prop": "body_fx_amount", "value": 1.0],
        ]], rebuildPlayer: false)
        selectedID = EngineClipAddress(track: et, clip: ci).idString
        return true
    }

    // MARK: - FX levers

    /// Drop an effect on a target. Video effects on a content track couple to
    /// the overlapped clip engine-side; the GFX rail hosts global bricks.
    /// Returns false when the engine rejected the placement (error published).
    @discardableResult
    func placeEffect(_ effect: EffectDef, onto target: DropTarget, at t: Double) -> Bool {
        var params = Dictionary(uniqueKeysWithValues: effect.params.map { ($0.key, $0.def) })
        params.removeValue(forKey: "dry_wet")

        let hostTrack: Int
        let r: [String: Any]?
        switch target {
        case .clip(let clipID):
            guard let ti = trackIndex(ofClip: clipID), tracks[ti].engineIndex >= 0 else { return false }
            hostTrack = tracks[ti].engineIndex
            r = mutate("add_effect_brick", [
                "track": hostTrack, "fx_type": effect.id,
                "start": t, "end": t + 2, "params": params,
            ], rebuildPlayer: false)
        case .audioClip(let clipID):
            guard let ti = trackIndex(ofClip: clipID), tracks[ti].engineIndex >= 0 else { return false }
            hostTrack = tracks[ti].engineIndex
            r = mutate("add_audio_multifx_brick", [
                "track": hostTrack, "start": t, "end": t + 4,
                "effects": [["fx_type": effect.id, "params": params] as [String: Any]],
            ], rebuildPlayer: false)
        case .fxRail:
            guard let gfx = ensureTrack(.fxRail) else { return false }
            hostTrack = gfx
            r = mutate("add_effect_brick", [
                "track_name": "GFX", "fx_type": effect.id,
                "start": t, "end": t + 3, "params": params,
            ], rebuildPlayer: false)
        case .brick(let brickID):
            weld(effect.id, intoBrick: brickID)
            return true
        }
        guard let ci = r?["clip"] as? Int else { return false }
        selectedID = EngineClipAddress(track: hostTrack, clip: ci).idString
        return true
    }

    /// Weld an effect into an existing brick → the chain contract is
    /// delete + recreate as a Multi-FX brick (add_multifx_brick CREATES;
    /// it never mutates an existing brick).
    func weld(_ effectID: String, intoBrick brickID: String) {
        guard let r = locate(brickID), r.kind == .brick, let a = address(brickID) else { return }
        let b = tracks[r.track].bricks[r.index]
        guard b.kind == .glassFX || b.kind == .multiFX || b.kind == .globalFX else { return }
        var entries = b.chainEntries()
        entries.append(["fx_type": effectID, "params": [String: Double]()])
        // delete + recreate is compound: batch it so a rejected recreate rolls
        // the deletion back (abort_batch) instead of destroying the brick.
        engine.send("begin_batch", ["label": "Weld FX"])
        guard (try? engine.result("delete_clip", ["track": a.track, "clip": a.clip])) != nil else {
            engine.send("abort_batch")
            refresh(rebuildPlayer: false); return
        }
        let reply = try? engine.resultObject("add_multifx_brick", [
            "track": a.track, "start": b.start, "end": b.end, "effects": entries,
        ])
        if reply == nil {
            engine.send("abort_batch")   // restores the deleted brick
            refresh(rebuildPlayer: false)
            return
        }
        engine.send("end_batch")
        undoDepth += 1; redoDepth = 0
        refresh(rebuildPlayer: false)
        if let ci = reply?["clip"] as? Int {
            selectedID = EngineClipAddress(track: a.track, clip: ci).idString
        }
    }

    /// Decouple a welded brick from its host clip.
    func decouple(_ brickID: String) {
        guard let a = address(brickID) else { return }
        _ = mutate("decouple_fx_brick", ["track": a.track, "clip": a.clip], rebuildPlayer: false)
        selectedID = nil   // decouple re-hosts the brick on a new track
    }

    /// Live slider — local + shader immediately; the engine lever debounced.
    /// Body bricks route through set_clip_prop (positional body_fx_param_i);
    /// everything else through set_clip_fx.
    func setParam(_ key: String, _ value: Double, onBrick id: String) {
        guard let b = binding(forBrick: id) else { return }
        b.wrappedValue.params[key] = value
        syncLiveFX()
        guard let a = address(id) else { return }
        let isBody = b.wrappedValue.kind == .bodyFX
        let fxID = b.wrappedValue.chain.last
        paramCommitTask?.cancel()
        paramCommitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            if isBody {
                _ = self?.mutate("set_clip_prop", ["track": a.track, "clip": a.clip,
                                                   "prop": key, "value": value],
                                 rebuildPlayer: false)
            } else if let fxID {
                _ = self?.mutate("set_clip_fx", ["track": a.track, "clip": a.clip,
                                                 "fx_id": fxID, "params": [key: value]],
                                 rebuildPlayer: false)
            }
        }
    }

    func deleteBrick(_ id: String) { deleteSelected(id) }

    /// While RecordView owns the live stack (record-scoped looks), timeline
    /// refreshes must not clobber it — RecordView sets this for its lifetime.
    var liveFXSuspended = false

    /// Push the current video-FX stack to the Metal render adapter. Built from
    /// the ENGINE projection (never a separate Swift brick array); goes away
    /// once pms_render derives the same stack from AppState directly.
    func syncLiveFX() {
        guard !liveFXSuspended else { return }
        var stack: [[String: Any]] = []
        for tr in tracks {
            for b in tr.bricks {
                switch b.kind {
                case .glassFX, .multiFX, .globalFX:
                    let perFX = b.chainParams(padTo: b.chain.count)
                    for (i, fxID) in b.chain.enumerated() {
                        stack.append(["fx_type": fxID, "params": perFX[i],
                                      "start": b.start, "end": b.end])
                    }
                case .bodyFX:
                    guard let name = b.bodyFXType else { continue }
                    // Metal body passes take the real BodyFXInfo param names;
                    // the projection stores positional keys — map via the def.
                    var named: [String: Double] = [:]
                    if let def = bodyDef(named: name) {
                        for (i, p) in def.params.enumerated() {
                            named[p.key] = b.params["body_fx_param_\(i)"] ?? p.def
                        }
                    }
                    named["amount"] = b.params["body_fx_amount"] ?? 1.0
                    stack.append(["fx_type": "body_fx", "body_fx_type": name,
                                  "params": named, "start": b.start, "end": b.end])
                case .audioFX:
                    break   // audio chains render engine-side, not in the video stack
                }
            }
        }
        stack.sort { ($0["start"] as? Double ?? 0) < ($1["start"] as? Double ?? 0) }
        engine.send("set_live_fx", ["fx": stack])
    }

    // MARK: - Persistence

    /// Persist through the engine's binary .pms + the poster sidecar.
    func save() {
        guard !lastSnapshot.isEmpty || ProjectStore.exists(project.id) else { return }
        do {
            try ProjectStore.save(engine: engine, id: project.id, name: project.name)
            Task { await writePoster() }
        } catch { /* published to lastError */ }
    }

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

    var duration: Double { max(engineDuration, videoDuration ?? 0) }

    // MARK: - Derived

    func activeBricks(at t: Double) -> [Brick] {
        tracks.flatMap { $0.bricks }.filter { t >= $0.start && t < $0.end }
    }

    func activeVideoLabel(at t: Double) -> String {
        guard let v = tracks.first(where: { $0.kind == .video }), !v.clips.isEmpty else { return "" }
        return (v.clips.first { t >= $0.start && t < $0.end } ?? v.clips.last)?.label ?? ""
    }
}

extension Brick {
    /// Per-chain-entry params, padded/aligned to the chain length. The last
    /// stage always reflects `params` (the inspector's live binding).
    func chainParams(padTo n: Int) -> [[String: Double]] {
        var out = Array(repeating: [String: Double](), count: max(0, n))
        for i in 0..<min(n, chainParamsList.count) { out[i] = chainParamsList[i] }
        if !out.isEmpty { out[out.count - 1] = params }
        return out
    }

    /// `effects` array entries for add_multifx_brick / add_audio_multifx_brick,
    /// carrying per-entry params and body_fx_type where present.
    func chainEntries() -> [[String: Any]] {
        let perFX = chainParams(padTo: chain.count)
        return chain.enumerated().map { i, fxID in
            var e: [String: Any] = ["fx_type": fxID, "params": perFX[i]]
            if fxID == "body_fx", i < chainBodyTypes.count, let bt = chainBodyTypes[i] {
                e["body_fx_type"] = bt
            }
            return e
        }
    }
}

enum EditorSheet: Identifiable {
    case media, fx, lyrics, shape, agent, export
    var id: Int { hashValue }
}

enum DropTarget {
    case clip(String)       // effect brick on the clip's track (couples engine-side)
    case audioClip(String)  // audio FX chain brick
    case fxRail             // global FX on the GFX rail
    case brick(String)      // weld into an existing brick's chain
}
