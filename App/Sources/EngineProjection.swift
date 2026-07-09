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
            fxType: cj["fx_type"] as? String,
            fxParams: doubleDict(cj["fx_params"]),
            fxChain: chain,
            bodyFXType: cj["body_fx_type"] as? String)
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
}
