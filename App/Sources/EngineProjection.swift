//  EngineProjection.swift
//  The ONE decoder for engine project state. Screens never parse raw
//  [String: Any] themselves — they render the typed snapshot produced here.
//
//  Identity contract: the engine has no stable clip UUID. Every clip/brick is
//  addressed by (track index, clip index) — EngineClipAddress — and addresses
//  shift on insert/delete/split, so the projection is re-decoded after every
//  structural mutation and addresses are resolved fresh, never stored across one.

import Foundation

struct EngineClipAddress: Hashable {
    let track: Int
    let clip: Int
    /// Stable-for-this-projection SwiftUI id string.
    var idString: String { "t\(track)c\(clip)" }
}

struct EngineClipSnapshot: Identifiable {
    let address: EngineClipAddress
    var id: EngineClipAddress { address }
    var type: String            // engine clip_type_str: video/audio/text/lyrics/effect/multi_fx/audio_multi_fx/body_fx/...
    var start: Double
    var end: Double
    var inPoint: Double
    var text: String
    var source: String?
    var coupled: Bool
    var speed: Double
    var volume: Double
    var opacity: Double
    var muted: Bool
    var fadeIn: Double
    var fadeOut: Double
    var fontSize: Double
    var clipStyle: String
    // Canvas transform (fractions of canvas; engine base values — keyframes
    // project separately). CANVAS_PLAN.md.
    var posX: Double
    var posY: Double
    var scaleX: Double
    var scaleY: Double
    var rotation: Double            // degrees, clockwise
    var cropL: Double
    var cropT: Double
    var cropR: Double
    var cropB: Double
    var flipH: Bool
    var flipV: Bool
    // Text placement (canvas fractions; sub_* engine vocabulary)
    var subPos: Int                 // 0 bottom, 1 centre, 2 top, 3 custom Y
    var subPosX: Double             // horizontal centre fraction (0 left, 1 right)
    var subPosY: Double             // custom Y fraction from top (sub_pos == 3)
    var subAnchorH: Int             // 0 left, 1 centre, 2 right
    var subWrapW: Double            // column width as fraction of canvas width
    // FX bricks (type == effect / multi_fx / audio_multi_fx / body_fx)
    struct ChainEntry {
        var fxType: String
        var params: [String: Double]
        var bodyFXType: String?         // set when fxType == "body_fx" (names contain spaces)
    }
    var fxType: String?                 // effect id for single-effect bricks
    var fxParams: [String: Double]
    var fxChain: [ChainEntry]
    var bodyFXType: String?
    var duration: Double { end - start }

    var isFXBrick: Bool {
        type == "effect" || type == "multi_fx" || type == "audio_multi_fx" || type == "body_fx"
    }
    /// Ordered effect ids this brick applies (single or chain).
    var effectIDs: [String] {
        if !fxChain.isEmpty { return fxChain.map(\.fxType) }
        if let fxType { return [fxType] }
        return []
    }
}

struct EngineMarkerSnapshot: Identifiable {
    let id: Int                 // engine marker index
    var time: Double
    var label: String
    var colorHex: String
}

struct EngineTrackSnapshot: Identifiable {
    let id: Int                 // engine track index
    var name: String
    var muted: Bool
    var locked: Bool
    var clips: [EngineClipSnapshot]

    var contentClips: [EngineClipSnapshot] { clips.filter { !$0.isFXBrick } }
    var fxBricks: [EngineClipSnapshot] { clips.filter { $0.isFXBrick } }
}

struct EngineProjectSnapshot {
    var duration: Double = 0
    var fps: Double = 30
    var bpm: Double = 120
    var playhead: Double = 0
    var projectPath: String = ""
    var tracks: [EngineTrackSnapshot] = []
    var markers: [EngineMarkerSnapshot] = []
    var bin: [String] = []

    var isEmpty: Bool { tracks.allSatisfy { $0.clips.isEmpty } }

    subscript(_ a: EngineClipAddress) -> EngineClipSnapshot? {
        guard a.track >= 0, a.track < tracks.count,
              a.clip >= 0, a.clip < tracks[a.track].clips.count else { return nil }
        return tracks[a.track].clips[a.clip]
    }

    func firstTrack(named name: String) -> EngineTrackSnapshot? {
        tracks.first { $0.name == name }
    }
    /// First track carrying (or named for) a content kind: "video"/"audio"/"text".
    func firstTrackIndex(withClipType type: String) -> Int? {
        tracks.firstIndex { $0.clips.contains { $0.type == type } }
    }

    // MARK: decode

    /// Decode `get_project(verbose: true)`'s result object.
    static func decode(_ r: [String: Any]) -> EngineProjectSnapshot {
        var s = EngineProjectSnapshot()
        s.duration = num(r["duration"]) ?? 0
        s.fps = num(r["fps"]) ?? 30
        s.bpm = num(r["bpm"]).flatMap { $0 > 0 ? $0 : nil } ?? 120
        s.playhead = num(r["playhead"]) ?? 0
        s.projectPath = r["project_path"] as? String ?? ""
        s.bin = r["bin"] as? [String] ?? []
        if let tracks = r["tracks"] as? [[String: Any]] {
            s.tracks = tracks.enumerated().map { ti, tj in
                let index = (tj["index"] as? Int) ?? ti
                var t = EngineTrackSnapshot(id: index,
                                            name: tj["name"] as? String ?? "Track \(index)",
                                            muted: tj["muted"] as? Bool ?? false,
                                            locked: tj["locked"] as? Bool ?? false,
                                            clips: [])
                if let clips = tj["clips"] as? [[String: Any]] {
                    t.clips = clips.enumerated().map { ci, cj in
                        decodeClip(cj, at: EngineClipAddress(track: index, clip: (cj["index"] as? Int) ?? ci))
                    }
                }
                return t
            }
        }
        if let markers = r["markers"] as? [[String: Any]] {
            s.markers = markers.enumerated().map { mi, mj in
                EngineMarkerSnapshot(id: (mj["index"] as? Int) ?? mi,
                                     time: num(mj["time"]) ?? 0,
                                     label: mj["label"] as? String ?? "",
                                     colorHex: mj["color"] as? String ?? "#4A90E2")
            }
        }
        return s
    }

    private static func decodeClip(_ cj: [String: Any], at address: EngineClipAddress) -> EngineClipSnapshot {
        var chain: [EngineClipSnapshot.ChainEntry] = []
        if let raw = cj["fx_chain"] as? [[String: Any]] {
            chain = raw.map { e in
                EngineClipSnapshot.ChainEntry(fxType: e["fx_type"] as? String ?? "",
                                              params: doubleDict(e["fx_params"]),
                                              bodyFXType: e["body_fx_type"] as? String)
            }
        }
        return EngineClipSnapshot(
            address: address,
            type: cj["type"] as? String ?? "unknown",
            start: num(cj["start"]) ?? 0,
            end: num(cj["end"]) ?? 0,
            inPoint: num(cj["in_point"]) ?? 0,
            text: cj["text"] as? String ?? "",
            source: cj["source"] as? String,
            coupled: cj["coupled"] as? Bool ?? false,
            speed: num(cj["speed"]) ?? 1,
            volume: num(cj["volume"]) ?? 1,
            opacity: num(cj["opacity"]) ?? 1,
            muted: cj["muted"] as? Bool ?? false,
            fadeIn: num(cj["fade_in"]) ?? 0,
            fadeOut: num(cj["fade_out"]) ?? 0,
            fontSize: num(cj["font_size"]) ?? 0,
            clipStyle: cj["clip_style"] as? String ?? "",
            posX: num(cj["pos_x"]) ?? 0.5,
            posY: num(cj["pos_y"]) ?? 0.5,
            scaleX: num(cj["scale_x"]) ?? 1,
            scaleY: num(cj["scale_y"]) ?? 1,
            rotation: num(cj["rotation"]) ?? 0,
            cropL: num(cj["crop_l"]) ?? 0,
            cropT: num(cj["crop_t"]) ?? 0,
            cropR: num(cj["crop_r"]) ?? 0,
            cropB: num(cj["crop_b"]) ?? 0,
            flipH: cj["flip_h"] as? Bool ?? false,
            flipV: cj["flip_v"] as? Bool ?? false,
            subPos: (cj["sub_pos"] as? Int) ?? Int(num(cj["sub_pos"]) ?? 0),
            subPosX: num(cj["sub_pos_x"]) ?? 0.5,
            subPosY: num(cj["sub_pos_y"]) ?? 0.85,
            subAnchorH: (cj["sub_anchor_h"] as? Int) ?? Int(num(cj["sub_anchor_h"]) ?? 1),
            subWrapW: num(cj["sub_wrap_w"]) ?? 0.85,
            fxType: cj["fx_type"] as? String,
            fxParams: bodyAwareParams(cj),
            fxChain: chain,
            bodyFXType: cj["body_fx_type"] as? String)
    }

    /// fx_params for regular effect bricks; for body_fx clips, fold the engine's
    /// positional body_fx_params[4] + body_fx_amount into set_clip_prop keys
    /// (body_fx_param_i / body_fx_amount) so the inspector round-trips them.
    private static func bodyAwareParams(_ cj: [String: Any]) -> [String: Double] {
        var out = doubleDict(cj["fx_params"])
        if let amount = num(cj["body_fx_amount"]) { out["body_fx_amount"] = amount }
        if let arr = cj["body_fx_params"] as? [Any] {
            for (i, v) in arr.enumerated() { if let d = num(v) { out["body_fx_param_\(i)"] = d } }
        }
        return out
    }

    private static func num(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }
    private static func doubleDict(_ v: Any?) -> [String: Double] {
        guard let obj = v as? [String: Any] else { return [:] }
        var out: [String: Double] = [:]
        for (k, val) in obj { if let d = num(val) { out[k] = d } }
        return out
    }
}

// MARK: - Engine snapshot → UI projection (Track/Clip/Brick view structs)

extension EngineProjectSnapshot {
    /// Infer the UI lane kind for an engine track (the engine has no track kind;
    /// we create tracks with conventional names and infer from content otherwise).
    func uiKind(of t: EngineTrackSnapshot) -> TrackKind {
        if t.name == "GFX" || t.name == "FX" { return .fxRail }
        let content = t.contentClips
        if content.contains(where: { $0.type == "video" || $0.type == "video_record" }) { return .video }
        if content.contains(where: { $0.type == "audio" || $0.type == "record" }) { return .audio }
        if content.contains(where: { $0.type == "text" || $0.type == "lyrics" || $0.type == "subtitle" }) { return .lyric }
        // Empty track: fall back to name conventions used at creation time.
        if t.name.hasPrefix("V") { return .video }
        if t.name.hasPrefix("A") { return .audio }
        if t.name.hasPrefix("T") { return .lyric }
        return .video
    }

    private func brickKind(_ c: EngineClipSnapshot, onRail: Bool) -> BrickKind {
        switch c.type {
        case "multi_fx":       return .multiFX
        case "audio_multi_fx": return .audioFX
        case "body_fx":        return .bodyFX
        default:               return onRail ? .globalFX : .glassFX
        }
    }

    /// Build the UI track list. `media` resolves an engine source path to the
    /// runtime info AVFoundation owns (filmstrips, true source duration);
    /// `resolve` maps an engine source path to a readable file URL (iOS app
    /// containers move between installs, so stale absolute paths are relinked
    /// into the project's media/ dir by basename).
    func uiTracks(media: (String) -> MediaInfo?,
                  resolve: (String) -> URL? = { URL(fileURLWithPath: $0) }) -> [Track] {
        tracks.map { t in
            let kind = uiKind(of: t)
            var track = Track(id: "trk\(t.id)", kind: kind, name: t.name, clips: [])
            track.muted = t.muted
            track.locked = t.locked
            track.engineIndex = t.id
            for c in t.contentClips {
                let info = c.source.flatMap(media)
                var clip = Clip(id: c.address.idString,
                                label: c.text.isEmpty ? (c.source.map { URL(fileURLWithPath: $0).lastPathComponent } ?? c.type.uppercased()) : c.text,
                                start: c.start, duration: c.duration,
                                thumbs: info?.thumbs ?? [],
                                sourceURL: c.source.flatMap(resolve),
                                sourceStart: c.inPoint,
                                sourceDuration: info?.duration ?? 0,
                                speed: c.speed)
                clip.fadeIn = c.fadeIn
                clip.fadeOut = c.fadeOut
                clip.address = c.address
                clip.sourceSize = info?.size
                clip.posX = c.posX; clip.posY = c.posY
                clip.scaleX = c.scaleX; clip.scaleY = c.scaleY
                clip.rotation = c.rotation
                clip.cropL = c.cropL; clip.cropT = c.cropT
                clip.cropR = c.cropR; clip.cropB = c.cropB
                clip.flipH = c.flipH; clip.flipV = c.flipV
                clip.textKind = (c.type == "text" || c.type == "lyrics" || c.type == "subtitle")
                clip.fontSize = c.fontSize
                clip.subPos = c.subPos
                clip.subPosX = c.subPosX; clip.subPosY = c.subPosY
                clip.subAnchorH = c.subAnchorH
                clip.subWrapW = c.subWrapW
                clip.clipStyle = c.clipStyle
                track.clips.append(clip)
            }
            for b in t.fxBricks {
                var brick = Brick(id: b.address.idString,
                                  kind: brickKind(b, onRail: kind == .fxRail),
                                  start: b.start, duration: b.duration,
                                  chain: b.effectIDs)
                // Params: single-effect bricks carry fx_params; chains keep the
                // last stage's params editable in the inspector.
                brick.params = b.fxChain.last?.params ?? b.fxParams
                brick.chainParamsList = b.fxChain.map(\.params)
                brick.chainBodyTypes = b.fxChain.map(\.bodyFXType)
                brick.coupled = b.coupled
                brick.address = b.address
                brick.bodyFXType = b.bodyFXType ?? b.fxChain.compactMap(\.bodyFXType).first
                track.bricks.append(brick)
            }
            return track
        }
    }
}

/// Runtime-only metadata AVFoundation owns per media file (never persisted).
struct MediaInfo {
    var duration: Double
    var thumbs: [URL]
    var size: CGSize? = nil     // display size (naturalSize ∘ preferredTransform)
}
