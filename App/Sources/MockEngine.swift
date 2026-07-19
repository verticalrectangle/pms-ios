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
        // Canvas transform (engine defaults; fractions of canvas)
        var posX = 0.5, posY = 0.5
        var scaleX = 1.0, scaleY = 1.0
        var rotation = 0.0
        var cropL = 0.0, cropT = 0.0, cropR = 0.0, cropB = 0.0
        var flipH = false, flipV = false
        var subPos = 0
        var subPosX = 0.5, subPosY = 0.85
        var subAnchorH = 1
        var subWrapW = 0.85
        var coupled = false
        var fxType = ""                       // effect bricks
        var fxParams: [String: Double] = [:]
        var fxChain: [MChainEntry] = []       // multi_fx / audio_multi_fx
        var bodyFXType = ""
        // Shape clips (ClipType::Shape)
        var shapePreset = ""              // UI label only
        var shapePath: MockShapePath = MockShapePath()
        var shapeStyle: MockShapeStyle = MockShapeStyle()
        var shapeKeys: [MockShapeKey] = []
        var shapeStrokeLength = 1.0
        var shapeStrokeWidthMul = 1.0
        var keyTimes: [String: [Double]] = [:]   // prop → key times (mock ktracks)
        var isFX: Bool { type == "effect" || type == "multi_fx" || type == "audio_multi_fx" || type == "body_fx" }
    }
    struct MockShapePath: Codable { var points: [MockShapePoint] = []; var closed = false }
    struct MockShapePoint: Codable { var x: Double; var y: Double; var w: Double }
    struct MockShapeStyle: Codable {
        var fillCol: [Double] = [1,1,1,1]; var fillOn = true
        var strokeCol: [Double] = [1,1,1,1]; var strokeOn = false
        var strokeWidth = 0.008; var gradMode = 0
        var gradCol2: [Double] = [1,0.3,0.6,1]; var gradAngle = 0.0
        var glowCol: [Double] = [1,1,1,1]; var glowOn = false
        var glowRadius = 0.02; var glowIntensity = 1.0
    }
    struct MockShapeKey: Codable { var t: Double; var path: MockShapePath; var interp = "ease_both" }
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
    private var selectedTrack = -1, selectedClip = -1   // canvas selection (runtime-only)
    private var inBatch = false                          // history coalescing (begin/end/abort_batch)
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

        case "move_track":
            guard let from = params["from"] as? Int, from >= 0, from < state.tracks.count else {
                return err("track index out of range")
            }
            var to = params["to"] as? Int ?? 0
            to = max(0, min(to, state.tracks.count - 1))
            push()
            let moved = state.tracks.remove(at: from)
            state.tracks.insert(moved, at: to)
            return ok(["track": to, "order": state.tracks.map(\.name)])

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

        case "add_shape":
            guard let ti = trackIndex(params) else { return err("track index out of range") }
            let preset = params["preset"] as? String ?? "circle"
            guard Self.bakePreset(preset) != nil else { return err("unknown preset '\(preset)'") }
            push()
            var c = MClip()
            c.type = "shape"
            c.start = dbl(params["start"]) ?? 0
            c.end = dbl(params["end"]) ?? c.start + 3
            c.shapePreset = preset
            c.shapePath = Self.bakePreset(preset)!
            // Outline presets read better stroke-on (mirrors the engine).
            if preset == "lightning" || preset == "arrow" || preset == "burst" {
                c.shapeStyle.fillOn = false; c.shapeStyle.strokeOn = true
            }
            state.tracks[ti].clips.append(c)
            return ok(["clip": state.tracks[ti].clips.count - 1, "preset": preset])

        case "set_shape_path":
            guard let (ti, ci) = clipAddress(params) else { return err("bad clip address") }
            guard state.tracks[ti].clips[ci].type == "shape" else { return err("clip is not a shape") }
            guard let pts = params["points"] as? [[String: Any]] else { return err("points array required") }
            push()
            var path = MockShapePath()
            path.closed = params["closed"] as? Bool ?? false
            path.points = pts.map { MockShapePoint(x: dbl($0["x"]) ?? 0.5, y: dbl($0["y"]) ?? 0.5,
                                                   w: dbl($0["w"]) ?? 0.008) }
            state.tracks[ti].clips[ci].shapePath = path
            state.tracks[ti].clips[ci].shapePreset = "Freehand"
            return ok([:])

        case "set_shape_style":
            guard let (ti, ci) = clipAddress(params) else { return err("bad clip address") }
            guard state.tracks[ti].clips[ci].type == "shape" else { return err("clip is not a shape") }
            push()
            var s = state.tracks[ti].clips[ci].shapeStyle
            if let v = params["fill_on"] as? Bool { s.fillOn = v }
            if let v = params["stroke_on"] as? Bool { s.strokeOn = v }
            if let v = dbl(params["stroke_width"]) { s.strokeWidth = v }
            if let v = params["grad_mode"] as? Int { s.gradMode = v }
            if let v = dbl(params["grad_angle"]) { s.gradAngle = v }
            if let v = params["glow_on"] as? Bool { s.glowOn = v }
            if let v = dbl(params["glow_radius"]) { s.glowRadius = v }
            if let v = dbl(params["glow_intensity"]) { s.glowIntensity = v }
            if let a = params["fill_col"] as? [Any] { s.fillCol = a.map { dbl($0) ?? 0 } }
            if let a = params["stroke_col"] as? [Any] { s.strokeCol = a.map { dbl($0) ?? 0 } }
            if let a = params["grad_col2"] as? [Any] { s.gradCol2 = a.map { dbl($0) ?? 0 } }
            if let a = params["glow_col"] as? [Any] { s.glowCol = a.map { dbl($0) ?? 0 } }
            state.tracks[ti].clips[ci].shapeStyle = s
            return ok([:])

        case "set_shape_keyframes":
            guard let (ti, ci) = clipAddress(params) else { return err("bad clip address") }
            guard state.tracks[ti].clips[ci].type == "shape" else { return err("clip is not a shape") }
            push()
            var keys: [MockShapeKey] = []
            for k in params["keys"] as? [[String: Any]] ?? [] {
                let pts = (k["points"] as? [[String: Any]] ?? []).map { MockShapePoint(x: dbl($0["x"]) ?? 0.5, y: dbl($0["y"]) ?? 0.5, w: dbl($0["w"]) ?? 0.008) }
                keys.append(MockShapeKey(t: dbl(k["t"]) ?? 0,
                                         path: MockShapePath(points: pts, closed: k["closed"] as? Bool ?? false),
                                         interp: k["interp"] as? String ?? "ease_both"))
            }
            keys.sort { $0.t < $1.t }
            state.tracks[ti].clips[ci].shapeKeys = keys
            return ok(["key_count": keys.count])

        case "get_shape_path":
            guard let (ti, ci) = clipAddress(params) else { return err("bad clip address") }
            guard state.tracks[ti].clips[ci].type == "shape" else { return err("clip is not a shape") }
            let c = state.tracks[ti].clips[ci]
            // No real interpolation in the mock — return the base path, or the
            // nearest key if morph keys exist.
            var path = c.shapePath
            if let t = dbl(params["t"]), !c.shapeKeys.isEmpty {
                path = c.shapeKeys.min(by: { abs($0.t - t) < abs($1.t - t) })?.path ?? path
            }
            return ok([
                "closed": path.closed,
                "points": path.points.map { ["x": $0.x, "y": $0.y, "w": $0.w] as [String: Any] },
                "key_count": c.shapeKeys.count
            ] as [String: Any])

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

        case "set_clip_keyframes":
            guard let (ti, ci) = clipAddress(params) else { return err("bad clip address") }
            let prop = params["prop"] as? String ?? ""
            // Mock models the keyframable shape props + opacity; other props
            // are accepted but only their key times are tracked.
            let allowed = ["opacity", "shape_stroke_length", "shape_stroke_width_mul",
                           "pos_x", "pos_y", "scale_x", "scale_y", "rotation"]
            guard allowed.contains(prop) else { return err("prop '\(prop)' is not keyframable") }
            guard let keys = params["keys"] as? [[String: Any]] else { return err("keys array required") }
            push()
            var times: [Double] = []
            for k in keys { if let t = dbl(k["t"]) { times.append(t) } }
            times.sort()
            if times.isEmpty { state.tracks[ti].clips[ci].keyTimes.removeValue(forKey: prop) }
            else { state.tracks[ti].clips[ci].keyTimes[prop] = times }
            return ok(["prop": prop, "key_count": times.count])

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

        case "set_live_fx":
            return ok([:])

        // Record-mode camera plumbing (no-op render path in the mock).
        case "clear_layer_frames":
            return ok([:])
        case "face_track_enable":
            return ok(["on": (params["on"] as? Bool) ?? true, "models_present": false])
        case "face_debug":
            return ok(["models_present": false, "feed_enabled": false,
                       "valid": false, "score": 0.0, "has_blend": false])

        // Batches mirror the engine: one history entry per batch; abort rolls
        // back to the begin_batch snapshot.
        case "begin_batch":
            guard !inBatch else { return err("already in a batch") }
            push()
            inBatch = true
            return ok([:])
        case "end_batch":
            guard inBatch else { return err("not in a batch") }
            inBatch = false
            return ok([:])
        case "abort_batch":
            guard inBatch else { return err("not in a batch") }
            inBatch = false
            if let prev = undoStack.popLast() { state = prev }
            return ok([:])

        case "select_clip":
            // Canvas selection (runtime-only, like the engine's
            // state.selected_track/clip — never serialized).
            guard let ci = params["clip"] as? Int, ci >= 0 else {
                selectedTrack = -1; selectedClip = -1
                return ok([:])
            }
            guard let (ti, vci) = clipAddress(params) else { return err("bad clip address") }
            selectedTrack = ti; selectedClip = vci
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
        guard !inBatch else { return }   // batch = one entry, captured at begin_batch
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
        case "pos_x":     c.posX = dbl(value) ?? c.posX
        case "pos_y":     c.posY = dbl(value) ?? c.posY
        case "scale_x":   c.scaleX = dbl(value) ?? c.scaleX
        case "scale_y":   c.scaleY = dbl(value) ?? c.scaleY
        case "rotation":  c.rotation = dbl(value) ?? c.rotation
        // Crop clamps mirror the engine: each side is limited to 0.95 minus
        // its opposite so a sliver of the frame always survives.
        case "crop_l":    c.cropL = max(0, min(dbl(value) ?? 0, 0.95 - c.cropR))
        case "crop_r":    c.cropR = max(0, min(dbl(value) ?? 0, 0.95 - c.cropL))
        case "crop_t":    c.cropT = max(0, min(dbl(value) ?? 0, 0.95 - c.cropB))
        case "crop_b":    c.cropB = max(0, min(dbl(value) ?? 0, 0.95 - c.cropT))
        case "flip_h":    c.flipH = value as? Bool ?? c.flipH
        case "flip_v":    c.flipV = value as? Bool ?? c.flipV
        case "sub_pos":   c.subPos = (value as? Int) ?? Int(dbl(value) ?? Double(c.subPos))
        case "sub_pos_x": c.subPosX = dbl(value) ?? c.subPosX
        case "sub_pos_y": c.subPosY = dbl(value) ?? c.subPosY
        case "sub_anchor_h": c.subAnchorH = (value as? Int) ?? Int(dbl(value) ?? Double(c.subAnchorH))
        case "sub_wrap_w": c.subWrapW = dbl(value) ?? c.subWrapW
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
            "pos_x": c.posX, "pos_y": c.posY,
            "scale_x": c.scaleX, "scale_y": c.scaleY, "rotation": c.rotation,
            "crop_l": c.cropL, "crop_t": c.cropT, "crop_r": c.cropR, "crop_b": c.cropB,
            "flip_h": c.flipH, "flip_v": c.flipV,
            "sub_pos": c.subPos, "sub_pos_x": c.subPosX, "sub_pos_y": c.subPosY,
            "sub_anchor_h": c.subAnchorH, "sub_wrap_w": c.subWrapW,
        ]
        if !c.source.isEmpty { j["source"] = c.source }
        if c.coupled { j["coupled"] = true }
        if c.type == "effect" { j["fx_type"] = c.fxType; j["fx_params"] = c.fxParams }
        if !c.fxChain.isEmpty {
            j["fx_chain"] = c.fxChain.map { ["fx_type": $0.fxType, "fx_params": $0.fxParams] as [String: Any] }
        }
        if c.type == "body_fx" { j["body_fx_type"] = c.bodyFXType.isEmpty ? "Neon Outline" : c.bodyFXType }
        if c.type == "shape" {
            j["shape_path"] = [
                "closed": c.shapePath.closed,
                "points": c.shapePath.points.map { ["x": $0.x, "y": $0.y, "w": $0.w] as [String: Any] }
            ] as [String: Any]
            j["shape_style"] = [
                "fill_col": c.shapeStyle.fillCol, "fill_on": c.shapeStyle.fillOn,
                "stroke_col": c.shapeStyle.strokeCol, "stroke_on": c.shapeStyle.strokeOn,
                "stroke_width": c.shapeStyle.strokeWidth, "grad_mode": c.shapeStyle.gradMode,
                "grad_col2": c.shapeStyle.gradCol2, "grad_angle": c.shapeStyle.gradAngle,
                "glow_col": c.shapeStyle.glowCol, "glow_on": c.shapeStyle.glowOn,
                "glow_radius": c.shapeStyle.glowRadius, "glow_intensity": c.shapeStyle.glowIntensity
            ] as [String: Any]
            j["shape_stroke_length"] = c.shapeStrokeLength
            j["shape_stroke_width_mul"] = c.shapeStrokeWidthMul
            if !c.shapeKeys.isEmpty {
                j["shape_path_keys"] = c.shapeKeys.map { k in
                    ["t": k.t, "closed": k.path.closed,
                     "points": k.path.points.map { ["x": $0.x, "y": $0.y, "w": $0.w] as [String: Any] },
                     "interp": k.interp] as [String: Any]
                }
            }
        }
        if !c.keyTimes.isEmpty {
            var kfs: [String: Any] = [:]
            for (prop, times) in c.keyTimes {
                kfs[prop] = times.map { ["t": $0, "v": 1.0, "interp": "ease_both"] as [String: Any] }
            }
            j["keyframes"] = kfs
        }
        return j
    }

    /// Bake a preset path in local [0,1]² space (mock approximation — the real
    /// tessellation lives in the engine). Enough points to look right in the
    /// timeline preview and round-trip through set_shape_path.
    private static func bakePreset(_ name: String) -> MockShapePath? {
        let cx = 0.5, cy = 0.5, r = 0.4
        let P = Double.pi
        func pt(_ a: Double, rr: Double = r) -> MockShapePoint {
            MockShapePoint(x: cx + rr * cos(a), y: cy + rr * sin(a), w: 0.008)
        }
        switch name {
        case "circle":
            var p = MockShapePath(closed: true)
            for i in 0..<48 { p.points.append(pt(Double(i) / 48 * P * 2)) }
            return p
        case "square":
            return MockShapePath(points: [MockShapePoint(x: 0.1, y: 0.1, w: 0.008), MockShapePoint(x: 0.9, y: 0.1, w: 0.008),
                                          MockShapePoint(x: 0.9, y: 0.9, w: 0.008), MockShapePoint(x: 0.1, y: 0.9, w: 0.008)], closed: true)
        case "triangle":
            return MockShapePath(points: [pt(-P / 2), pt(P / 6), pt(5 * P / 6)], closed: true)
        case "diamond":
            return MockShapePath(points: [pt(-P / 2), pt(0), pt(P / 2), pt(P)], closed: true)
        case "hexagon":
            var p = MockShapePath(closed: true)
            for i in 0..<6 { p.points.append(pt(Double(i) / 6 * P * 2)) }
            return p
        case "polygon":
            var p = MockShapePath(closed: true)
            for i in 0..<5 { p.points.append(pt(Double(i) / 5 * P * 2 - P / 2)) }
            return p
        case "star":
            var p = MockShapePath(closed: true)
            for i in 0..<10 {
                let a = Double(i) / 10 * P * 2 - P / 2
                p.points.append(pt(a, rr: i % 2 == 0 ? r : r * 0.4))
            }
            return p
        case "burst":
            var p = MockShapePath(closed: true)
            for i in 0..<24 {
                let a = Double(i) / 24 * P * 2
                p.points.append(pt(a, rr: i % 2 == 0 ? r : r * 0.6))
            }
            return p
        case "heart":
            var p = MockShapePath(closed: true)
            for i in 0..<48 {
                let t = Double(i) / 48 * P * 2
                let x = 16 * pow(sin(t), 3)
                let y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
                p.points.append(MockShapePoint(x: cx + x / 40, y: cy - y / 40, w: 0.008))
            }
            return p
        case "arrow":
            return MockShapePath(points: [MockShapePoint(x: 0.1, y: 0.45, w: 0.008), MockShapePoint(x: 0.7, y: 0.45, w: 0.008),
                                          MockShapePoint(x: 0.7, y: 0.3, w: 0.008), MockShapePoint(x: 0.9, y: 0.5, w: 0.008),
                                          MockShapePoint(x: 0.7, y: 0.7, w: 0.008), MockShapePoint(x: 0.7, y: 0.55, w: 0.008),
                                          MockShapePoint(x: 0.1, y: 0.55, w: 0.008)], closed: true)
        case "lightning":
            return MockShapePath(points: [MockShapePoint(x: 0.55, y: 0.1, w: 0.008), MockShapePoint(x: 0.35, y: 0.5, w: 0.008),
                                          MockShapePoint(x: 0.5, y: 0.5, w: 0.008), MockShapePoint(x: 0.4, y: 0.9, w: 0.008),
                                          MockShapePoint(x: 0.65, y: 0.45, w: 0.008), MockShapePoint(x: 0.5, y: 0.45, w: 0.008),
                                          MockShapePoint(x: 0.6, y: 0.1, w: 0.008)], closed: true)
        case "cross":
            return MockShapePath(points: [MockShapePoint(x: 0.4, y: 0.1, w: 0.008), MockShapePoint(x: 0.6, y: 0.1, w: 0.008),
                                          MockShapePoint(x: 0.6, y: 0.4, w: 0.008), MockShapePoint(x: 0.9, y: 0.4, w: 0.008),
                                          MockShapePoint(x: 0.9, y: 0.6, w: 0.008), MockShapePoint(x: 0.6, y: 0.6, w: 0.008),
                                          MockShapePoint(x: 0.6, y: 0.9, w: 0.008), MockShapePoint(x: 0.4, y: 0.9, w: 0.008),
                                          MockShapePoint(x: 0.4, y: 0.6, w: 0.008), MockShapePoint(x: 0.1, y: 0.6, w: 0.008),
                                          MockShapePoint(x: 0.1, y: 0.4, w: 0.008), MockShapePoint(x: 0.4, y: 0.4, w: 0.008)], closed: true)
        default: return nil
        }
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
