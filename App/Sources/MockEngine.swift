//  MockEngine.swift
//  Simulator-only stand-in for the C++ engine (the Intel Mac's x86_64 simulator
//  has no engine slice). It models the REAL command contract — integer
//  track/clip addresses, rejection of bad payloads, project queries, undo/redo,
//  save/load — so UI bugs surface in the simulator instead of hiding until a
//  device build. It is NOT the engine: its .pms files are mock-JSON and only
//  ever live in the simulator sandbox.

#if ENGINE_MOCK
import Foundation

final class MockEngine {

    // MARK: model (mirrors the engine's JSON vocabulary)

    struct MClip: Codable {
        var type = "text"
        var start = 0.0, end = 2.0
        var inPoint = 0.0
        var text = ""
        var source = ""
        var speed = 1.0, volume = 1.0, opacity = 1.0
        var muted = false
        var fadeIn = 0.0, fadeOut = 0.0
        var fontSize = 42.0
        var clipStyle = "none"
        var coupled = false
        var fxType = ""                       // effect bricks
        var fxParams: [String: Double] = [:]
        var fxChain: [MChainEntry] = []       // multi_fx / audio_multi_fx
        var bodyFXType = ""
        var isFX: Bool { type == "effect" || type == "multi_fx" || type == "audio_multi_fx" || type == "body_fx" }
    }
    struct MChainEntry: Codable { var fxType: String; var fxParams: [String: Double] = [:] }
    struct MTrack: Codable {
        var name = "Track"
        var muted = false, locked = false
        var clips: [MClip] = []
    }
    struct MMarker: Codable { var time: Double; var label: String; var color: String }
    struct MState: Codable {
        var format = "vertical"
        var fps = 30.0, bpm = 0.0
        var playhead = 0.0
        var projectPath = ""
        var tracks: [MTrack] = []
        var markers: [MMarker] = []
        var bin: [String] = []
    }

    private var state = MState()
    private var playing = false
    private var undoStack: [MState] = []
    private var redoStack: [MState] = []
    private var recentProjects: [String] = []

    var playheadIsAdvancing: Bool { playing }
    func tick(_ dt: Double) { if playing { state.playhead += dt } }

    // MARK: dispatch

    func command(_ method: String, _ params: [String: Any]) -> [String: Any] {
        switch method {
        case "play":  playing = true;  return ok([:])
        case "pause": playing = false; return ok([:])
        case "seek":  state.playhead = max(0, dbl(params["time"]) ?? 0); return ok([:])

        case "get_project":   return ok(projectJSON())
        case "get_all_clips": return ok(["tracks": allClipsJSON()])   // callers use get_project; kept simple

        case "new_project":
            let hasContent = state.tracks.contains { !$0.clips.isEmpty }
            if hasContent && !(params["force"] as? Bool ?? false) {
                return err("Refused: new_project wipes the current project — pass force=true.")
            }
            state = MState(); undoStack = []; redoStack = []
            return ok([:])

        case "set_format":
            let f = params["format"] as? String ?? ""
            let map = ["vertical": "vertical", "9:16": "vertical",
                       "horizontal": "horizontal", "16:9": "horizontal",
                       "square": "square", "1:1": "square"]
            guard let canon = map[f] else { return err("unknown format: \(f)") }
            push(); state.format = canon
            return ok([:])

        case "add_track":
            push()
            var pos = params["position"] as? Int ?? 0
            pos = max(0, min(pos, state.tracks.count))
            state.tracks.insert(MTrack(name: params["name"] as? String ?? "Track"), at: pos)
            return ok(["track": pos])

        case "add_clip":
            guard let ti = trackIndex(params) else { return err("track index out of range") }
            push()
            var c = MClip()
            c.type = params["type"] as? String ?? "text"
            c.start = dbl(params["start"]) ?? 0
            c.end = dbl(params["end"]) ?? c.start + 2
            c.text = params["text"] as? String ?? ""
            if c.type == "video" || c.type == "audio" {
                c.source = c.text
                if !c.text.isEmpty, !state.bin.contains(c.text) { state.bin.append(c.text) }
            }
            state.tracks[ti].clips.append(c)
            return ok(["clip": state.tracks[ti].clips.count - 1])

        case "move_clip":
            guard let (ti, ci) = clipAddress(params) else { return err("bad clip address") }
            push()
            let dur = state.tracks[ti].clips[ci].end - state.tracks[ti].clips[ci].start
            let s = dbl(params["start"]) ?? 0
            state.tracks[ti].clips[ci].start = s
            state.tracks[ti].clips[ci].end = s + dur
            return ok([:])

        case "trim_clip":
            guard let (ti, ci) = clipAddress(params) else { return err("bad clip address") }
            push()
            var c = state.tracks[ti].clips[ci]
            if let ns = dbl(params["start"]) {
                c.inPoint = max(0, c.inPoint + (ns - c.start) * max(0.01, c.speed))
                c.start = ns
            }
            if let ne = dbl(params["end"]) { c.end = ne }
            state.tracks[ti].clips[ci] = c
            return ok([:])

        case "split_clip":
            guard let (ti, ci) = clipAddress(params) else { return err("bad clip address") }
            guard let t = dbl(params["time"]) else { return err("missing 'time' or 'times'") }
            let c = state.tracks[ti].clips[ci]
            guard t > c.start, t < c.end else {
                return err(String(format: "split time %.3f outside clip range %.3f-%.3f", t, c.start, c.end))
            }
            push()
            var left = c, right = c
            left.end = t
            right.start = t
            right.inPoint = c.inPoint + (t - c.start) * max(0.01, c.speed)
            right.fadeIn = 0; left.fadeOut = 0
            state.tracks[ti].clips.replaceSubrange(ci...ci, with: [left, right])
            return ok(["left_clip": ci, "right_clip": ci + 1])

        case "delete_clip":
            guard let (ti, ci) = clipAddress(params) else { return err("bad clip address") }
            push()
            state.tracks[ti].clips.remove(at: ci)
            return ok(["deleted_clip": ci, "clips_remaining": state.tracks[ti].clips.count])

        case "set_clip_prop":
            guard let (ti, ci) = clipAddress(params) else { return err("bad clip address") }
            push()
            guard applyProp(&state.tracks[ti].clips[ci],
                            params["prop"] as? String ?? "", params["value"]) else {
                return err("unknown prop: \(params["prop"] as? String ?? "")")
            }
            return ok([:])

        case "set_clip_props":
            guard let ops = params["ops"] as? [[String: Any]] else { return err("ops array required") }
            push()
            for op in ops {
                guard let (ti, ci) = clipAddress(op) else { return err("bad clip address") }
                guard applyProp(&state.tracks[ti].clips[ci],
                                op["prop"] as? String ?? "", op["value"]) else {
                    return err("unknown prop: \(op["prop"] as? String ?? "")")
                }
            }
            return ok([:])

        case "add_effect_brick":
            guard let ti = trackIndex(params) else { return err("track index out of range") }
            push()
            var c = MClip()
            c.type = "effect"
            c.fxType = params["fx_type"] as? String ?? "grade"
            c.start = dbl(params["start"]) ?? 0
            c.end = dbl(params["end"]) ?? c.start + 2
            c.fxParams = doubleDict(params["params"])
            c.coupled = overlapsContent(ti, c.start, c.end)
            state.tracks[ti].clips.append(c)
            return ok(["clip": state.tracks[ti].clips.count - 1, "coupled": c.coupled])

        case "add_multifx_brick", "add_audio_multifx_brick":
            guard let ti = trackIndex(params) else { return err("track index out of range") }
            push()
            var c = MClip()
            c.type = method == "add_multifx_brick" ? "multi_fx" : "audio_multi_fx"
            c.start = dbl(params["start"]) ?? 0
            c.end = dbl(params["end"]) ?? c.start + 2
            for e in params["effects"] as? [[String: Any]] ?? [] {
                c.fxChain.append(MChainEntry(fxType: e["fx_type"] as? String ?? "grade",
                                             fxParams: doubleDict(e["params"])))
            }
            c.coupled = overlapsContent(ti, c.start, c.end)
            state.tracks[ti].clips.append(c)
            return ok(["clip": state.tracks[ti].clips.count - 1, "coupled": c.coupled])

        case "set_clip_fx":
            guard let (ti, ci) = clipAddress(params) else { return err("bad clip address") }
            guard let fxID = params["fx_id"] as? String, !fxID.isEmpty else { return err("fx_id is required") }
            push()
            var c = state.tracks[ti].clips[ci]
            for (k, v) in doubleDict(params["params"]) {
                if !c.fxChain.isEmpty {
                    if let i = c.fxChain.lastIndex(where: { $0.fxType == fxID }) { c.fxChain[i].fxParams[k] = v }
                } else {
                    c.fxParams[k] = v
                }
            }
            state.tracks[ti].clips[ci] = c
            return ok([:])

        case "decouple_fx_brick":
            guard let (ti, ci) = clipAddress(params) else { return err("bad clip address") }
            guard state.tracks[ti].clips[ci].coupled else { return err("clip is not a coupled FX brick") }
            push()
            state.tracks[ti].clips[ci].coupled = false
            return ok([:])

        case "add_marker":
            push()
            let m = MMarker(time: dbl(params["time"]) ?? 0,
                            label: params["label"] as? String ?? "",
                            color: params["color"] as? String ?? "#4A90E2")
            let idx = state.markers.firstIndex { $0.time > m.time } ?? state.markers.count
            state.markers.insert(m, at: idx)
            return ok(["index": idx])

        case "add_to_bin":
            guard let p = params["path"] as? String, !p.isEmpty else { return err("path required") }
            if !state.bin.contains(p) { state.bin.append(p) }
            return ok(["path": p, "bin_size": state.bin.count])
        case "remove_from_bin":
            guard let p = params["path"] as? String else { return err("path required") }
            state.bin.removeAll { $0 == p }
            return ok(["path": p, "bin_size": state.bin.count])

        case "undo":
            guard let prev = undoStack.popLast() else { return err("nothing to undo") }
            redoStack.append(state); state = prev
            return ok(projectJSON())
        case "redo":
            guard let next = redoStack.popLast() else { return err("nothing to redo") }
            undoStack.append(state); state = next
            return ok(projectJSON())

        case "begin_batch", "end_batch", "abort_batch", "set_live_fx", "select_clip":
            return ok([:])

        case "list_body_fx":
            // Mirrors the engine's BodyFXInfo table shape (subset for the sim).
            func p(_ n: String, _ l: String, _ mn: Double, _ mx: Double, _ d: Double) -> [String: Any] {
                ["name": n, "label": l, "min": mn, "max": mx, "default": d]
            }
            return ok(["effects": [
                ["name": "Neon Outline", "tagline": "glow along the silhouette", "category": "Body",
                 "params": [p("width", "Width", 1, 8, 3), p("glow", "Glow", 0, 2, 1)]],
                ["name": "Depth Blur", "tagline": "sharp person, blurred world", "category": "Body",
                 "params": [p("radius", "Blur Radius", 2, 30, 12)]],
                ["name": "Body Glitch", "tagline": "slice the silhouette", "category": "Body",
                 "params": [p("intensity", "Intensity", 0, 1, 0.4), p("speed", "Speed", 0.1, 4, 1)]],
            ] as [[String: Any]]])

        case "save_project":
            guard let path = params["path"] as? String, !path.isEmpty else { return err("no project path") }
            do {
                let data = try JSONEncoder().encode(state)
                try data.write(to: URL(fileURLWithPath: path), options: .atomic)
                state.projectPath = path
                if !recentProjects.contains(path) { recentProjects.insert(path, at: 0) }
                return ok(["path": path])
            } catch { return err("project_save failed: \(error.localizedDescription)") }

        case "load_project":
            guard let path = params["path"] as? String, !path.isEmpty else { return err("path is required") }
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let s = try? JSONDecoder().decode(MState.self, from: data) else {
                return err("project_load failed")
            }
            state = s
            state.projectPath = path
            undoStack = []; redoStack = []
            return ok(["path": path])

        case "get_project_summary":
            guard let path = params["path"] as? String,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let s = try? JSONDecoder().decode(MState.self, from: data) else {
                return err("unreadable project")
            }
            return ok(Self.summary(of: s, at: path))

        case "list_recent_projects":
            let sums: [[String: Any]] = recentProjects.compactMap { path in
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                      let s = try? JSONDecoder().decode(MState.self, from: data) else { return nil }
                return Self.summary(of: s, at: path)
            }
            return ok(["projects": sums])

        default:
            // Model rejection — hiding unknown commands behind a fake OK is how
            // wrong payloads survive until a device build.
            return err("unknown method (mock): \(method)")
        }
    }

    // MARK: helpers

    private func ok(_ r: [String: Any]) -> [String: Any] { ["id": "ui", "result": r] }
    private func err(_ e: String) -> [String: Any] { ["id": "ui", "error": e] }

    private func dbl(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }
    private func doubleDict(_ v: Any?) -> [String: Double] {
        guard let o = v as? [String: Any] else { return [:] }
        var out: [String: Double] = [:]
        for (k, val) in o { if let d = dbl(val) { out[k] = d } }
        return out
    }

    /// track by "track" index or "track_name" (mirrors track_by_name_or_index).
    private func trackIndex(_ params: [String: Any]) -> Int? {
        if let name = params["track_name"] as? String {
            return state.tracks.firstIndex { $0.name == name }
        }
        guard let ti = params["track"] as? Int, ti >= 0, ti < state.tracks.count else { return nil }
        return ti
    }
    private func clipAddress(_ params: [String: Any]) -> (Int, Int)? {
        guard let ti = trackIndex(params),
              let ci = params["clip"] as? Int, ci >= 0, ci < state.tracks[ti].clips.count else { return nil }
        return (ti, ci)
    }
    private func overlapsContent(_ ti: Int, _ s: Double, _ e: Double) -> Bool {
        state.tracks[ti].clips.contains { !$0.isFX && $0.start < e && $0.end > s }
    }
    private func push() {
        undoStack.append(state)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func applyProp(_ c: inout MClip, _ prop: String, _ value: Any?) -> Bool {
        switch prop {
        case "volume":    c.volume = dbl(value) ?? c.volume
        case "opacity":   c.opacity = dbl(value) ?? c.opacity
        case "muted":     c.muted = value as? Bool ?? c.muted
        case "speed":     c.speed = dbl(value) ?? c.speed
        case "fade_in":   c.fadeIn = dbl(value) ?? c.fadeIn
        case "fade_out":  c.fadeOut = dbl(value) ?? c.fadeOut
        case "text":      c.text = value as? String ?? c.text
        case "font_size": c.fontSize = dbl(value) ?? c.fontSize
        case "clip_style": c.clipStyle = value as? String ?? c.clipStyle
        case "body_fx_type": c.bodyFXType = value as? String ?? c.bodyFXType
        case "body_fx_amount": c.fxParams["body_fx_amount"] = dbl(value) ?? 0
        case "body_fx_param_0", "body_fx_param_1", "body_fx_param_2", "body_fx_param_3":
            c.fxParams[prop] = dbl(value) ?? 0
        default: return false
        }
        return true
    }

    // MARK: JSON projections (same field names as ipc_server.cpp)

    private var timelineDuration: Double {
        state.tracks.flatMap(\.clips).map(\.end).max() ?? 0
    }

    private func clipJSON(_ ci: Int, _ c: MClip) -> [String: Any] {
        var j: [String: Any] = [
            "index": ci, "type": c.type, "start": c.start, "end": c.end,
            "duration": c.end - c.start, "in_point": c.inPoint, "text": c.text,
            "volume": c.volume, "speed": c.speed, "opacity": c.opacity,
            "muted": c.muted, "fade_in": c.fadeIn, "fade_out": c.fadeOut,
            "font_size": c.fontSize, "clip_style": c.clipStyle,
        ]
        if !c.source.isEmpty { j["source"] = c.source }
        if c.coupled { j["coupled"] = true }
        if c.type == "effect" { j["fx_type"] = c.fxType; j["fx_params"] = c.fxParams }
        if !c.fxChain.isEmpty {
            j["fx_chain"] = c.fxChain.map { ["fx_type": $0.fxType, "fx_params": $0.fxParams] as [String: Any] }
        }
        if c.type == "body_fx" { j["body_fx_type"] = c.bodyFXType.isEmpty ? "Neon Outline" : c.bodyFXType }
        return j
    }

    private func projectJSON() -> [String: Any] {
        [
            "duration": timelineDuration, "fps": state.fps, "bpm": state.bpm,
            "playhead": state.playhead, "project_path": state.projectPath,
            "format": state.format,
            "tracks": state.tracks.enumerated().map { ti, t in
                ["index": ti, "name": t.name, "muted": t.muted, "locked": t.locked,
                 "clips": t.clips.enumerated().map { clipJSON($0, $1) }] as [String: Any]
            },
            "markers": state.markers.enumerated().map { mi, m in
                ["index": mi, "time": m.time, "label": m.label, "color": m.color] as [String: Any]
            },
            "bin": state.bin,
        ]
    }

    private func allClipsJSON() -> [[String: Any]] {
        state.tracks.enumerated().map { ti, t in
            ["index": ti, "name": t.name,
             "clips": t.clips.enumerated().map { clipJSON($0, $1) }] as [String: Any]
        }
    }

    private static func summary(of s: MState, at path: String) -> [String: Any] {
        let clips = s.tracks.flatMap(\.clips)
        let mtime = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)
            .flatMap { $0 } ?? Date()
        return [
            "path": path,
            "name": URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
            "duration": clips.map(\.end).max() ?? 0,
            "fps": s.fps,
            "format": s.format,
            "clip_count": clips.filter { !$0.isFX }.count,
            "fx_count": clips.filter { $0.isFX }.count,
            "modified_unix": Int(mtime.timeIntervalSince1970),
        ]
    }
}
#endif
