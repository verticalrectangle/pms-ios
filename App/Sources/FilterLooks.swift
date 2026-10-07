// FilterLooks.swift — curated record-mode looks. A Look is an ordered stack of
// catalog effects (1–3 entries) pushed through set_live_fx while the camera is
// live, then welded onto the finished take as an ordinary Multi-FX brick — so
// every look is non-destructive, editable afterwards, and renders identically
// on desktop (all ids come from the shared engine manifest; nothing iOS-only).
import Foundation

struct Look: Identifiable, Equatable {
    enum Category: String, CaseIterable, Identifiable {
        case forYou = "For You"
        case makeup = "Makeup"
        case beauty = "Beauty"
        case color = "Color"
        case trippy = "Trippy"
        case cyberpunk = "Cyberpunk"
        case chroma = "Chroma"
        var id: String { rawValue }
    }

    /// One FX-stack entry: a manifest effect id + param overrides (unset params
    /// ride the catalog defaults, filled in at push time). `faceLook` names an
    /// ARKit makeup look for face_fx entries (engine asset
    /// models/face/arkit/<faceLook>.json).
    struct Entry: Equatable {
        let fx: String
        var params: [String: Double] = [:]
        var faceLook: String? = nil
    }

    let id: String
    let name: String
    let icon: String           // SF Symbol for the carousel bubble
    let categories: [Category]
    let stack: [Entry]

    static let none = Look(id: "none", name: "No Filter", icon: "circle.slash",
                           categories: Category.allCases, stack: [])

    static func == (a: Look, b: Look) -> Bool { a.id == b.id }
}

enum FilterLooks {
    /// The full deck, in rail order. Looks whose effects are missing from the
    /// running catalog (older engine) are filtered out at access time.
    static let all: [Look] = [
        // ── Makeup (ARKit TrueDepth face mesh — front camera) ────────────────
        // A makeup look is engine data: models/face/arkit/<faceLook>.json plus
        // the masks it names (engine tools/gen_arkit_makeup.py).
        Look(id: "egirl", name: "E-Girl", icon: "heart.circle.fill",
             categories: [.forYou, .makeup],
             stack: [.init(fx: "face_fx", faceLook: "egirl")]),

        // ── Beauty (full-frame skin filters — no tracking; makeup lives above) ────────────
        Look(id: "glass_skin", name: "Glass Skin", icon: "drop.fill",
             categories: [.beauty],
             stack: [.init(fx: "glass_skin")]),
        Look(id: "glow_up", name: "Glow Up", icon: "wand.and.stars",
             categories: [.beauty],
             stack: [.init(fx: "glow_up")]),
        Look(id: "retro_beauty", name: "Retro Beauty", icon: "camera.filters",
             categories: [.beauty],
             stack: [.init(fx: "retro_beauty")]),

        // ── Color ────────────────────────────────────────────────────────────
        Look(id: "golden_hour", name: "Golden Hour", icon: "sunset.fill",
             categories: [.forYou, .color],
             stack: [.init(fx: "golden_hour")]),
        Look(id: "miami", name: "Miami Vice", icon: "flame.fill",
             categories: [.color],
             stack: [.init(fx: "miami_vice")]),
        Look(id: "film", name: "Film Look", icon: "film",
             categories: [.color],
             stack: [.init(fx: "grade", params: ["contrast": 1.12, "saturation": 0.9]),
                     .init(fx: "film_grain"),
                     .init(fx: "vignette", params: ["vignette": 0.35])]),
        Look(id: "duotone", name: "Duotone", icon: "circle.lefthalf.filled",
             categories: [.color],
             stack: [.init(fx: "duotone")]),
        Look(id: "thermal", name: "Thermal", icon: "thermometer.sun.fill",
             categories: [.color],
             stack: [.init(fx: "thermal")]),
        Look(id: "night_vision", name: "Night Vision", icon: "eye.fill",
             categories: [.color],
             stack: [.init(fx: "night_vision")]),

        // ── Trippy ───────────────────────────────────────────────────────────
        Look(id: "acid", name: "Acid Trip", icon: "swirl.circle.righthalf.filled",
             categories: [.forYou, .trippy],
             stack: [.init(fx: "acid_trip")]),
        Look(id: "marble", name: "Liquid Marble", icon: "water.waves",
             categories: [.trippy],
             stack: [.init(fx: "liquid_marble")]),
        Look(id: "fractal", name: "Fractal Mirror", icon: "hexagon.fill",
             categories: [.trippy],
             stack: [.init(fx: "fractal_mirror")]),
        Look(id: "breathe", name: "Breathe", icon: "circle.dotted.circle",
             categories: [.trippy],
             stack: [.init(fx: "breathe_warp")]),
        Look(id: "melt", name: "Melt Drip", icon: "drop.triangle.fill",
             categories: [.trippy],
             stack: [.init(fx: "melt_drip")]),
        Look(id: "kaleido", name: "Kaleido", icon: "aqi.medium",
             categories: [.trippy],
             stack: [.init(fx: "kaleidoscope")]),
        Look(id: "holo", name: "Holographic", icon: "rainbow",
             categories: [.trippy],
             stack: [.init(fx: "holographic")]),

        // ── Cyberpunk ────────────────────────────────────────────────────────
        Look(id: "neon_city", name: "Neon City", icon: "building.2.fill",
             categories: [.forYou, .cyberpunk],
             stack: [.init(fx: "neon_city"),
                     .init(fx: "chromatic_aberration", params: ["amount": 0.5])]),
        Look(id: "night_drive", name: "Night Drive", icon: "car.fill",
             categories: [.forYou, .cyberpunk],
             stack: [.init(fx: "night_drive")]),
        Look(id: "chrome", name: "Chrome Pulse", icon: "bolt.circle.fill",
             categories: [.cyberpunk],
             stack: [.init(fx: "chrome_pulse")]),
        Look(id: "hud", name: "HUD Glitch", icon: "viewfinder",
             categories: [.cyberpunk],
             stack: [.init(fx: "hud_glitch")]),
        Look(id: "cyber_grade", name: "Cyberpunk", icon: "cpu.fill",
             categories: [.cyberpunk],
             stack: [.init(fx: "cyberpunk_grade")]),
        Look(id: "neon_glow", name: "Neon Glow", icon: "lightbulb.max.fill",
             categories: [.cyberpunk],
             stack: [.init(fx: "neon_glow")]),
        Look(id: "matrix", name: "Matrix Rain", icon: "terminal.fill",
             categories: [.cyberpunk],
             stack: [.init(fx: "matrix_rain")]),

        // ── Chroma FX (the desktop feedback family, now on Metal) ───────────
        // On camera these key on the PERSON MATTE (matte_key) — the background
        // melts/echoes behind you, no green screen. Tap the preview to switch
        // to a sampled colour key instead (RecordView keyOverride).
        Look(id: "chroma_melt", name: "Chroma Melt", icon: "waveform.path",
             categories: [.forYou, .chroma],
             stack: [.init(fx: "chroma_melt", params: ["matte_key": 1])]),
        Look(id: "chroma_echo", name: "Chroma Echo", icon: "square.stack.3d.down.right.fill",
             categories: [.chroma],
             stack: [.init(fx: "chroma_echo", params: ["matte_key": 1])]),
        Look(id: "chroma_frame", name: "Chroma Frame", icon: "square.stack.3d.forward.dottedline",
             categories: [.chroma],
             stack: [.init(fx: "chroma_frame", params: ["matte_key": 1])]),
        Look(id: "chroma_key", name: "Chroma Key", icon: "person.crop.rectangle.fill",
             categories: [.chroma],
             stack: [.init(fx: "chroma_key")]),
        Look(id: "vhs", name: "VHS", icon: "tv.fill",
             categories: [.chroma],
             stack: [.init(fx: "vhs")]),
        Look(id: "glitch", name: "Glitch", icon: "bolt.horizontal.fill",
             categories: [.chroma],
             stack: [.init(fx: "glitch")]),
    ]

    /// Engine-native stack entry types with no manifest card of their own.
    private static let engineNative: Set<String> = ["face_fx", "body_fx"]

    /// Looks for a rail category, [none] first, dropping looks whose effects
    /// the running catalog doesn't know (engine/manifest drift stays graceful).
    static func looks(in category: Look.Category) -> [Look] {
        [Look.none] + all.filter { look in
            look.categories.contains(category) &&
            look.stack.allSatisfy { EffectCatalog.byID[$0.fx] != nil || engineNative.contains($0.fx) }
        }
    }

    /// set_live_fx entries for a look at a given intensity: catalog defaults
    /// overlaid with the look's overrides; `amount` (wet/dry) rides intensity.
    /// face_fx entries take intensity as `face_amount` (look strength) and
    /// carry their look id as `face_look`.
    static func liveStack(for look: Look, intensity: Double) -> [[String: Any]] {
        look.stack.map { entry in
            var params: [String: Double] = [:]
            if let def = EffectCatalog.byID[entry.fx] {
                for p in def.params { params[p.key] = p.def }
            }
            for (k, v) in entry.params { params[k] = v }
            var e: [String: Any] = ["fx_type": entry.fx]
            if entry.fx == "face_fx" {
                params["face_amount"] = (entry.params["face_amount"] ?? 1.0) * intensity
                if let id = entry.faceLook { e["face_look"] = id }
            } else {
                // A look-authored amount is a per-entry ceiling; intensity scales it.
                params["amount"] = (entry.params["amount"] ?? 1.0) * intensity
            }
            e["params"] = params
            return e
        }
    }

    /// Legacy hand-wired engine FX have no per-clip `amount` field, and the
    /// engine rejects unknown params on brick creation — strip it there.
    private static let legacyIDs: Set<String> = [
        "grade", "blur", "vignette", "glitch", "zoom_punch", "lut", "light_leak",
        "vhs", "datamosh", "chroma_key", "chroma_melt", "chroma_echo", "chroma_frame",
    ]

    /// `effects` entries for add_multifx_brick — the bake-onto-the-take shape.
    /// `matte_key` is live-only (the timeline has no person matte yet), so a
    /// matte-keyed chroma look bakes with its colour key (tap-picked if the
    /// user sampled one; otherwise the classic green default). face_fx is
    /// dropped: takes record with looks BAKED INTO THE PIXELS
    /// (FilteredTakeRecorder), so a timeline brick would double-apply.
    static func brickEntries(for look: Look, intensity: Double) -> [[String: Any]] {
        liveStack(for: look, intensity: intensity).compactMap { e in
            var e = e
            guard let fx = e["fx_type"] as? String, fx != "face_fx" else { return nil }
            if legacyIDs.contains(fx), var p = e["params"] as? [String: Double] {
                p.removeValue(forKey: "amount")
                p.removeValue(forKey: "matte_key")
                e["params"] = p
            }
            return e
        }
    }
}