//  Models.swift
//  UI-side value types. These are a render-friendly PROJECTION of engine state
//  (decoded in EngineProjection.swift) — the engine remains the sole source of
//  truth. Every Clip/Brick carries the engine address it was decoded from;
//  mutations resolve that address and go through EngineStore levers.

import SwiftUI

// MARK: - Project library (home)

struct Project: Identifiable, Hashable {
    let id: String
    let name: String
    let sub: String
    let duration: Double        // seconds
    let format: Format
    let clipCount: Int
    let fxCount: Int
    let updated: String
    var live: Bool = false
    var isNew: Bool = false     // a fresh, empty project (nothing on disk yet)
    var posterURL: URL? = nil   // local first-frame poster sidecar

    /// A genuinely clean project — empty timeline, ready to import.
    static func blank() -> Project {
        Project(id: UUID().uuidString, name: "Untitled", sub: "New project",
                duration: 0, format: .portrait, clipCount: 0, fxCount: 0, updated: "now",
                isNew: true)
    }
}

enum Format: String, CaseIterable, Hashable {
    case portrait = "9:16"
    case landscape = "16:9"
    case square = "1:1"

    var aspect: CGFloat { switch self { case .portrait: 9.0/16; case .landscape: 16.0/9; case .square: 1 } }
    var resolution: String { switch self { case .portrait: "1080×1920"; case .landscape: "1920×1080"; case .square: "1080×1080" } }
    var pixelSize: (w: Int, h: Int) { switch self { case .portrait: (1080, 1920); case .landscape: (1920, 1080); case .square: (1080, 1080) } }
    var platform: String { switch self { case .portrait: "TikTok · Reels · Shorts"; case .landscape: "YouTube"; case .square: "Instagram" } }
    /// The `set_format` preset key (also what the engine reports back).
    var lever: String { switch self { case .portrait: "vertical"; case .landscape: "horizontal"; case .square: "square" } }

    init(engineFormat: String) {
        switch engineFormat {
        case "horizontal", "16:9": self = .landscape
        case "square", "1:1":      self = .square
        default:                   self = .portrait
        }
    }
}

// MARK: - Timeline (projection of engine tracks/clips)

enum TrackKind: String { case fxRail, video, lyric, audio }

struct Track: Identifiable {
    let id: String
    let kind: TrackKind
    let name: String
    var clips: [Clip]
    var bricks: [Brick] = []    // FX bricks riding on / over this track
    var muted = false
    var locked = false
    var engineIndex: Int = -1   // engine track index this lane was decoded from
}

/// A geometry lens over any timeline item (clip or brick) — lets one set of
/// move/trim/split/copy ops treat both uniformly without changing either struct.
protocol TimelineItem: Identifiable {
    var id: String { get set }
    var start: Double { get set }
    var duration: Double { get set }
    var end: Double { get }
}

struct Clip: Identifiable, TimelineItem {
    var id: String                 // address-derived ("t0c2"); regenerated every projection refresh
    var label: String
    var start: Double
    var duration: Double
    var thumbs: [URL] = []        // filmstrip — runtime only (AVFoundation owns it)
    var sourceURL: URL? = nil     // engine `source` path resolved to a file URL
    var sourceStart: Double = 0   // engine in_point (source seconds)
    var sourceDuration: Double = 0 // full source length (AVAsset probe; clamps trim)
    var speed: Double = 1.0       // source-consumption rate; srcTime = sourceStart + (t-start)*speed
    var fadeIn: Double = 0
    var fadeOut: Double = 0
    var address: EngineClipAddress? = nil   // where this clip lives in the engine
    var end: Double { start + duration }
}

/// UI flavour of an FX brick — derived from the engine clip type + host lane.
enum BrickKind: String {
    case glassFX      // effect brick on a content track → clip-scoped, pre-composite
    case globalFX     // effect brick on the GFX rail → post-composite
    case multiFX      // multi_fx chain brick
    case bodyFX       // body_fx silhouette brick
    case audioFX      // audio_multi_fx live audio chain
}

struct Brick: Identifiable, TimelineItem {
    var id: String                 // address-derived; regenerated every refresh
    var kind: BrickKind
    var start: Double
    var duration: Double
    /// Ordered effect ids this brick applies (one, or a chain).
    var chain: [String]
    var coupled: Bool = false          // engine fx_coupled (welded to content)
    var params: [String: Double] = [:]           // single brick / last chain stage (inspector binds here)
    var chainParamsList: [[String: Double]] = [] // per-entry params for chains (parallel to `chain`)
    var chainBodyTypes: [String?] = []           // per-entry body_fx_type (parallel to `chain`)
    var address: EngineClipAddress? = nil
    var bodyFXType: String? = nil      // BodyFXInfo name when kind == .bodyFX
    var end: Double { start + duration }

    var isChain: Bool { chain.count > 1 }
    var title: String {
        if let bodyFXType { return bodyFXType }
        if isChain { return "\(chain.count) FX" }
        return EffectCatalog.byID[chain.first ?? ""]?.name ?? (chain.first ?? "FX")
    }
}

// MARK: - Body FX (silhouette effects — defs come from the engine's list_body_fx)

struct BodyFXDef: Identifiable, Hashable {
    let name: String        // engine BodyFXInfo name, exact (contains spaces: "Neon Outline")
    let tagline: String
    let category: String
    let params: [EffectDef.Param]   // positional: params[i] edits body_fx_param_i
    var id: String { name }

    static func decode(_ e: [String: Any]) -> BodyFXDef? {
        guard let name = e["name"] as? String else { return nil }
        let params = (e["params"] as? [[String: Any]] ?? []).compactMap { p -> EffectDef.Param? in
            guard let key = p["name"] as? String else { return nil }
            func num(_ v: Any?) -> Double? { (v as? Double) ?? (v as? Int).map(Double.init) ?? (v as? NSNumber)?.doubleValue }
            return EffectDef.Param(key: key,
                                   label: p["label"] as? String ?? key,
                                   min: num(p["min"]) ?? 0,
                                   max: num(p["max"]) ?? 1,
                                   def: num(p["default"]) ?? 0.5,
                                   format: "%.2f")
        }
        return BodyFXDef(name: name,
                         tagline: e["tagline"] as? String ?? "",
                         category: e["category"] as? String ?? "Body",
                         params: params)
    }
}

// MARK: - Chapter markers (projection of engine markers)

struct ChapterMarker: Identifiable {
    var id = UUID()
    var time: Double
    var label: String
    var color: Color = Theme.accent

    init(time: Double, label: String, color: Color = Theme.accent) {
        self.time = time; self.label = label; self.color = color
    }
    init(_ m: EngineMarkerSnapshot) {
        time = m.time
        label = m.label
        color = Color(hex: m.colorHex) ?? Theme.accent
    }
}

extension Color {
    /// "#RRGGBB" → Color (engine marker colors).
    init?(hex: String) {
        var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if s.count == 8 { s = String(s.suffix(6)) }   // drop alpha if present
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}
