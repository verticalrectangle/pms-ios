//  Models.swift
//  UI-side value types. These mirror what the engine reports through get_project /
//  get_all_clips and what screens send back through pms_command levers. They are
//  plain Swift structs — the engine remains the source of truth; these are the
//  editable projection the SwiftUI screens render and mutate optimistically.

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
    let thumbSeed: String       // deterministic picsum seed
    var isNew: Bool = false     // a fresh, empty project (no mock demo content)

    var thumbURL: URL { URL(string: "https://picsum.photos/seed/\(thumbSeed)/240/320")! }

    /// A genuinely clean project — empty timeline, ready to import.
    static func blank() -> Project {
        Project(id: "new-\(UUID().uuidString.prefix(6))", name: "Untitled", sub: "New project",
                duration: 0, format: .portrait, clipCount: 0, fxCount: 0, updated: "now",
                thumbSeed: "new", isNew: true)
    }
}

enum Format: String, CaseIterable, Hashable {
    case portrait = "9:16"
    case landscape = "16:9"
    case square = "1:1"

    var aspect: CGFloat { switch self { case .portrait: 9.0/16; case .landscape: 16.0/9; case .square: 1 } }
    var resolution: String { switch self { case .portrait: "1080×1920"; case .landscape: "1920×1080"; case .square: "1080×1080" } }
    var platform: String { switch self { case .portrait: "TikTok · Reels · Shorts"; case .landscape: "YouTube"; case .square: "Instagram" } }
    /// The `set_format` preset key.
    var lever: String { switch self { case .portrait: "vertical"; case .landscape: "horizontal"; case .square: "square" } }
}

// MARK: - Timeline

enum TrackKind: String { case fxRail, video, lyric, audio }

struct Track: Identifiable {
    let id: String
    let kind: TrackKind
    let name: String
    var clips: [Clip]
    var bricks: [Brick] = []    // FX bricks riding on / over this track
    var muted = false
    var locked = false
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
    var id: String                 // var so copy/paste can regenerate it
    var label: String
    var start: Double
    var duration: Double
    var seed: String = "g1"
    var thumbs: [URL] = []      // filmstrip of sampled frames for imported clips
    var sourceURL: URL? = nil     // the video file this clip plays from
    var sourceStart: Double = 0   // in-point within the source (desktop in_point)
    var sourceDuration: Double = 0 // full length of the source (clamps trim)
    var speed: Double = 1.0       // source-consumption rate; srcTime = sourceStart + (t-start)*speed
    var fadeIn: Double = 0        // seconds ramping up from black at the clip's start
    var fadeOut: Double = 0       // seconds ramping down to black at the clip's end
    var end: Double { start + duration }
}

/// Every flavour of FX brick the engine supports. `scope`/`coupled` mirror the
/// glass-vs-global + weld semantics from add_effect_brick / decouple_fx_brick.
enum BrickKind {
    case glassFX      // add_effect_brick on a video track → clip-only, pre-composite
    case globalFX     // add_effect_brick on its own rail → everything below, post-composite
    case multiFX      // add_multifx_brick → ordered chain, one brick
    case bodyFX       // add_body_fx_brick → silhouette effect (needs process_body_fx_masks)
    case audioFX      // add_audio_multifx_brick → LIVE audio chain, auto-welds to clip
}

struct Brick: Identifiable, TimelineItem {
    var id: String                 // var so copy/paste can regenerate it
    var kind: BrickKind
    var start: Double
    var duration: Double
    /// One effect id, or an ordered chain (multiFX / audioFX).
    var chain: [String]
    var boundClipID: String? = nil     // set when welded/coupled to a content clip
    var params: [String: Double] = [:]
    var end: Double { start + duration }

    var isChain: Bool { chain.count > 1 }
    var title: String {
        if isChain { return "\(chain.count) FX" }
        return Effects.byID[chain.first ?? ""]?.name ?? (chain.first ?? "FX")
    }
}

// MARK: - Effect registry (subset of the engine's 109 GPU effects)

struct EffectDef: Identifiable, Hashable {
    let id: String          // engine effect id, e.g. "chromatic_aberration"
    let name: String        // display
    let category: String    // engine category
    let params: [Param]     // sliders → set_clip_fx
    struct Param: Hashable { let key: String; let min: Double; let max: Double; let def: Double }
}

enum Effects {
    static let categories = ["All", "Color", "Light", "Glitch", "Warp", "Motion", "Film", "Pattern", "Art", "Beauty"]

    /// A curated, real slice of the 109-effect library (ids + params match LEVERS.md).
    static let video: [EffectDef] = [
        .init(id: "chromatic_aberration", name: "Chromatic Aberration", category: "Glitch", params: [.init(key: "amount", min: 0, max: 1, def: 0.4)]),
        .init(id: "rgb_split", name: "RGB Split", category: "Glitch", params: [.init(key: "intensity", min: 0, max: 1, def: 0.3), .init(key: "speed", min: 0, max: 4, def: 1)]),
        .init(id: "glitch_block", name: "Glitch Block", category: "Glitch", params: [.init(key: "intensity", min: 0, max: 1, def: 0.4), .init(key: "speed", min: 0, max: 4, def: 1.5)]),
        .init(id: "pixel_sort", name: "Pixel Sort", category: "Glitch", params: [.init(key: "threshold", min: 0, max: 0.9, def: 0.35), .init(key: "intensity", min: 0, max: 1, def: 0.7)]),
        .init(id: "data_corrupt", name: "Data Corrupt", category: "Glitch", params: [.init(key: "density", min: 0, max: 0.5, def: 0.18), .init(key: "block_size", min: 2, max: 24, def: 8)]),
        .init(id: "pixelate", name: "Pixelate", category: "Glitch", params: [.init(key: "size", min: 1, max: 64, def: 12)]),

        .init(id: "duotone", name: "Duotone", category: "Color", params: [.init(key: "shadow_b", min: 0, max: 1, def: 0.2), .init(key: "highlight_g", min: 0, max: 1, def: 0.85)]),
        .init(id: "posterize", name: "Posterize", category: "Color", params: [.init(key: "levels", min: 2, max: 16, def: 4)]),
        .init(id: "cyberpunk_grade", name: "Cyberpunk", category: "Color", params: [.init(key: "shadow_teal", min: 0, max: 1, def: 0.9), .init(key: "contrast", min: 1, max: 2.5, def: 1.7)]),
        .init(id: "technicolor", name: "Technicolor", category: "Color", params: [.init(key: "saturation", min: 1, max: 4, def: 2), .init(key: "warmth", min: 0, max: 1, def: 0.35)]),
        .init(id: "kodachrome", name: "Kodachrome", category: "Color", params: [.init(key: "saturation", min: 0.8, max: 3, def: 1.5), .init(key: "reds", min: 0, max: 1, def: 0.5)]),
        .init(id: "golden_hour", name: "Golden Hour", category: "Color", params: [.init(key: "warmth", min: 0.1, max: 1, def: 0.8), .init(key: "glow_str", min: 0.1, max: 1, def: 0.7)]),

        .init(id: "neon_glow", name: "Neon Glow", category: "Light", params: [.init(key: "width", min: 1, max: 8, def: 3)]),
        .init(id: "bloom", name: "Bloom", category: "Light", params: [.init(key: "threshold", min: 0, max: 1, def: 0.55), .init(key: "intensity", min: 0, max: 4, def: 1.5)]),
        .init(id: "anamorphic_streak", name: "Anamorphic Flare", category: "Light", params: [.init(key: "length", min: 0, max: 1, def: 0.45), .init(key: "intensity", min: 0, max: 3, def: 1.2)]),
        .init(id: "god_rays", name: "God Rays", category: "Light", params: [.init(key: "intensity", min: 0, max: 2, def: 2.2), .init(key: "decay", min: 0.7, max: 1, def: 0.94)]),
        .init(id: "neon_edge_glow", name: "Neon Edges", category: "Light", params: [.init(key: "glow", min: 0.2, max: 2, def: 0.8), .init(key: "hue", min: 0, max: 1, def: 0.55)]),

        .init(id: "kaleidoscope", name: "Kaleidoscope", category: "Warp", params: [.init(key: "segments", min: 2, max: 16, def: 8), .init(key: "zoom", min: 0.5, max: 3, def: 0.55)]),
        .init(id: "ripple", name: "Ripple", category: "Warp", params: [.init(key: "frequency", min: 2, max: 40, def: 18), .init(key: "amplitude", min: 0.005, max: 0.1, def: 0.035)]),
        .init(id: "mirror_tunnel", name: "Mirror Tunnel", category: "Warp", params: [.init(key: "depth", min: 2, max: 12, def: 5), .init(key: "zoom", min: 0.3, max: 0.95, def: 0.65)]),
        .init(id: "tilt_shift", name: "Tilt-Shift", category: "Warp", params: [.init(key: "focus_band", min: 0.02, max: 0.5, def: 0.08), .init(key: "blur_radius", min: 2, max: 30, def: 12)]),

        .init(id: "echo_trails", name: "Echo Trails", category: "Motion", params: [.init(key: "offset", min: 0.005, max: 0.1, def: 0.025), .init(key: "fade", min: 0.1, max: 0.9, def: 0.55)]),
        .init(id: "zoom_blur_rad", name: "Zoom Streak", category: "Motion", params: [.init(key: "intensity", min: 0, max: 0.35, def: 0.12)]),
        .init(id: "cam_shake", name: "Cam Shake", category: "Motion", params: [.init(key: "intensity", min: 0, max: 1, def: 0.5), .init(key: "speed", min: 0.1, max: 4, def: 1)]),
        .init(id: "ken_burns", name: "Ken Burns", category: "Motion", params: [.init(key: "start_scale", min: 0.5, max: 4, def: 1), .init(key: "end_scale", min: 0.5, max: 4, def: 1.3)]),

        .init(id: "film_grain", name: "Film Grain", category: "Film", params: [.init(key: "intensity", min: 0, max: 1, def: 0.4), .init(key: "size", min: 0.5, max: 4, def: 1)]),
        .init(id: "super8_film", name: "Super 8", category: "Film", params: [.init(key: "grain", min: 0.05, max: 1.5, def: 0.5), .init(key: "gate", min: 0, max: 1, def: 0.4)]),
        .init(id: "film_halation", name: "Film Halation", category: "Film", params: [.init(key: "radius", min: 2, max: 20, def: 16), .init(key: "red_shift", min: 0, max: 1, def: 0.75)]),
        .init(id: "old_film", name: "Old Film", category: "Film", params: [.init(key: "sepia", min: 0, max: 1, def: 0.8), .init(key: "scratch", min: 0, max: 1, def: 0.4)]),

        .init(id: "crt", name: "CRT", category: "Pattern", params: [.init(key: "curvature", min: 0.05, max: 1, def: 0.35), .init(key: "glow", min: 0, max: 1, def: 0.3)]),
        .init(id: "scanlines", name: "Scanlines", category: "Pattern", params: [.init(key: "density", min: 1, max: 6, def: 2)]),
        .init(id: "halftone", name: "Halftone", category: "Pattern", params: [.init(key: "size", min: 2, max: 20, def: 6)]),
        .init(id: "matrix_rain", name: "Matrix", category: "Pattern", params: [.init(key: "density", min: 0, max: 1, def: 0.45), .init(key: "speed", min: 0.5, max: 6, def: 2)]),
        .init(id: "ascii_art", name: "ASCII Art", category: "Pattern", params: [.init(key: "char_size", min: 4, max: 24, def: 10)]),

        .init(id: "oil_paint", name: "Oil Paint", category: "Art", params: [.init(key: "radius", min: 2, max: 8, def: 4), .init(key: "sharpness", min: 0, max: 15, def: 6)]),
        .init(id: "watercolor", name: "Watercolor", category: "Art", params: [.init(key: "bleeding", min: 0.003, max: 0.05, def: 0.018)]),
        .init(id: "warhol_pop", name: "Pop Art", category: "Art", params: [.init(key: "levels", min: 2, max: 8, def: 4), .init(key: "saturation", min: 1, max: 4, def: 2.5)]),
        .init(id: "pencil_sketch", name: "Pencil Sketch", category: "Art", params: [.init(key: "line_str", min: 0.5, max: 5, def: 2.5)]),

        .init(id: "skin_smooth", name: "Skin Smooth", category: "Beauty", params: [.init(key: "radius", min: 1, max: 6, def: 3), .init(key: "tone", min: 0, max: 1, def: 0.5)]),
        .init(id: "glow_up", name: "Glow Up", category: "Beauty", params: [.init(key: "glow", min: 0, max: 1, def: 0.5), .init(key: "brighten", min: 0, max: 0.5, def: 0.15)]),
        .init(id: "glass_skin", name: "Glass Skin", category: "Beauty", params: [.init(key: "radius", min: 1, max: 6, def: 3.5), .init(key: "gloss", min: 0, max: 1, def: 0.5)]),
        .init(id: "retro_beauty", name: "Retro Beauty", category: "Beauty", params: [.init(key: "glow", min: 0, max: 1, def: 0.6), .init(key: "blush", min: 0, max: 1, def: 0.35)]),
    ]

    /// add_body_fx_brick / remove_background — silhouette-based, need process_body_fx_masks.
    static let body: [EffectDef] = [
        .init(id: "body_neon", name: "Neon Outline", category: "Body", params: [.init(key: "width", min: 1, max: 8, def: 3)]),
        .init(id: "body_depth_blur", name: "Depth Blur", category: "Body", params: [.init(key: "blur_radius", min: 2, max: 30, def: 12)]),
        .init(id: "body_glitch", name: "Body Glitch", category: "Body", params: [.init(key: "intensity", min: 0, max: 1, def: 0.4)]),
        .init(id: "body_retro_tv", name: "Retro TV", category: "Body", params: [.init(key: "curvature", min: 0.05, max: 1, def: 0.35)]),
        .init(id: "rvm_matte", name: "Remove Background", category: "Body", params: [.init(key: "similarity", min: 0.01, max: 1, def: 0.4)]),
    ]

    /// add_audio_multifx_brick — LIVE audio chain, auto-welds (1.5s) to the audio clip.
    static let audio: [EffectDef] = [
        .init(id: "aud_reverb", name: "Reverb", category: "Audio", params: [.init(key: "mix", min: 0, max: 1, def: 0.3), .init(key: "size", min: 0, max: 1, def: 0.6)]),
        .init(id: "aud_delay", name: "Delay", category: "Audio", params: [.init(key: "time", min: 0, max: 1, def: 0.25), .init(key: "feedback", min: 0, max: 0.95, def: 0.4)]),
        .init(id: "aud_autotune", name: "Auto-Tune", category: "Audio", params: [.init(key: "retune", min: 0, max: 1, def: 0.8)]),
        .init(id: "aud_comp", name: "Compressor", category: "Audio", params: [.init(key: "threshold", min: 0, max: 1, def: 0.5), .init(key: "ratio", min: 1, max: 20, def: 4)]),
        .init(id: "aud_lofi", name: "Lo-Fi", category: "Audio", params: [.init(key: "crush", min: 0, max: 1, def: 0.4)]),
    ]

    static let all: [EffectDef] = video + body + audio
    static let byID: [String: EffectDef] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
}

// MARK: - On-device AI actions (real levers + the local model each runs)

struct AIAction: Identifiable {
    let id = UUID()
    let title: String
    let lever: String       // the pms_command method
    let model: String       // the local model / method it runs
    let icon: String        // SF Symbol
    let busyLabel: String
}

enum AIActions {
    static let all: [AIAction] = [
        .init(title: "Describe scenes", lever: "describe_video",     model: "Moondream2", icon: "eye",                 busyLabel: "Captioning scenes…"),
        .init(title: "Find moment",     lever: "find_video_moment",  model: "scene search", icon: "sparkle.magnifyingglass", busyLabel: "Scoring captions…"),
        .init(title: "Remove background",lever: "remove_background", model: "RobustVideoMatting", icon: "person.crop.rectangle", busyLabel: "Matting alpha…"),
        .init(title: "Remove silence",  lever: "remove_silence",     model: "RMS energy", icon: "waveform.path",        busyLabel: "Scanning silence…"),
        .init(title: "Cut fillers",     lever: "cut_filler_words",   model: "transcript", icon: "scissors",            busyLabel: "Cutting um / uh…"),
        .init(title: "Analyze beats",   lever: "analyze_audio",      model: "beat / RMS", icon: "metronome",           busyLabel: "Detecting beats…"),
        .init(title: "Reframe",         lever: "crop_media",         model: "face detect", icon: "crop",               busyLabel: "Finding faces…"),
        .init(title: "Auto chapters",   lever: "generate_chapters",  model: "transcript", icon: "list.bullet.indent",  busyLabel: "Finding pauses…"),
    ]
}

// MARK: - Chapter markers (add_chapter_marker)

struct ChapterMarker: Identifiable { let id = UUID(); let time: Double; let label: String; let color: Color }

// MARK: - Sample project / scene (stand-in for get_project + get_all_clips)

enum Sample {
    static let bpm: Double = 128
    static let sceneDuration: Double = 18

    static let projects: [Project] = [
        .init(id: "p1",  name: "GLASS DROWN",  sub: "epsilver — single",           duration: 18,  format: .portrait,  clipCount: 7,  fxCount: 4,  updated: "2 min ago",   live: true, thumbSeed: "glassdrown"),
        .init(id: "p2",  name: "AMBER NIGHTS", sub: "Depravity Girlz",             duration: 204, format: .portrait,  clipCount: 22, fxCount: 11, updated: "Yesterday",   thumbSeed: "ambernights"),
        .init(id: "p3",  name: "DEAD CHANNEL", sub: "Ekioze — visualizer",         duration: 167, format: .landscape, clipCount: 14, fxCount: 8,  updated: "3 days ago",  thumbSeed: "deadchannel"),
        .init(id: "p4",  name: "WET CONCRETE", sub: "epsilver — b-side",           duration: 62,  format: .square,    clipCount: 9,  fxCount: 3,  updated: "Last week",   thumbSeed: "wetconcrete"),
        .init(id: "p5",  name: "VOID SIGNAL",  sub: "Ekioze — EP trailer",         duration: 45,  format: .portrait,  clipCount: 11, fxCount: 6,  updated: "2 weeks ago", thumbSeed: "voidsignal"),
        .init(id: "p6",  name: "SOFT MACHINE", sub: "Depravity Girlz — lyric vid", duration: 241, format: .portrait,  clipCount: 31, fxCount: 14, updated: "2 weeks ago", thumbSeed: "softmachine"),
        .init(id: "p7",  name: "NEON LITURGY", sub: "epsilver — album visual",     duration: 312, format: .landscape, clipCount: 44, fxCount: 22, updated: "3 weeks ago", thumbSeed: "neonliturgy"),
        .init(id: "p8",  name: "COLD STATIC",  sub: "Ekioze — loop pack",          duration: 30,  format: .square,    clipCount: 5,  fxCount: 2,  updated: "Last month",  thumbSeed: "coldstatic"),
        .init(id: "p9",  name: "RUST HYMNAL",  sub: "Depravity Girlz — b-side",    duration: 178, format: .portrait,  clipCount: 18, fxCount: 9,  updated: "Last month",  thumbSeed: "rusthymnal"),
        .init(id: "p10", name: "PRISM GATE",   sub: "epsilver — remix",            duration: 213, format: .portrait,  clipCount: 26, fxCount: 17, updated: "Last month",  thumbSeed: "prismgate"),
    ]

    // Track ORDER == layer z-order: index 0 = frontmost. FX rail on top, then
    // text (over video), video, audio base.
    static let tracks: [Track] = [
        Track(id: "GFX", kind: .fxRail, name: "FX", clips: [], bricks: [
            Brick(id: "gb1", kind: .globalFX, start: 13.4, duration: 4.6, chain: ["glitch_block"])
        ]),
        Track(id: "T1", kind: .lyric, name: "T1", clips: [
            Clip(id: "l1", label: "in the glass…",   start: 0.4,  duration: 4.6),
            Clip(id: "l2", label: "amber bleeding…", start: 5.4,  duration: 4.8),
            Clip(id: "l3", label: "hold the night…", start: 10.6, duration: 5.0),
        ]),
        Track(id: "V1", kind: .video, name: "V1", clips: [
            Clip(id: "c1", label: "EYE_CLOSEUP", start: 0,    duration: 6.4, seed: "eye"),
            Clip(id: "c2", label: "OCEAN_4K",    start: 6.4,  duration: 6.4, seed: "ocean"),
            Clip(id: "c3", label: "NEON_RUN",    start: 12.8, duration: 5.2, seed: "neon"),
        ], bricks: [
            Brick(id: "gl1", kind: .glassFX,  start: 2.0, duration: 2.0, chain: ["chromatic_aberration"], boundClipID: "c1"),
            Brick(id: "gl2", kind: .multiFX,  start: 8.6, duration: 3.8, chain: ["bloom", "film_halation"], boundClipID: "c2"),
            Brick(id: "bd1", kind: .bodyFX,   start: 13.0, duration: 4.6, chain: ["rvm_matte"], boundClipID: "c3"),
        ]),
        Track(id: "A1", kind: .audio, name: "A1", clips: [
            Clip(id: "a1", label: "glass_drown_master.wav", start: 0, duration: 18),
        ], bricks: [
            Brick(id: "au1", kind: .audioFX, start: 0, duration: 18, chain: ["aud_reverb", "aud_comp"], boundClipID: "a1"),
        ]),
    ]

    static let chapters: [ChapterMarker] = [
        .init(time: 0,    label: "INTRO", color: Theme.accent),
        .init(time: 6.4,  label: "VERSE", color: Theme.glassCyan),
        .init(time: 13.4, label: "DROP",  color: Theme.accent),
    ]
}
