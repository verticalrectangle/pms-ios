//  Palette.swift
//  The user-selectable accent color. Read through `Theme.accent`, so the whole
//  UI re-tints reactively — Observation records the `Palette.shared.accent`
//  access that happens inside every view body via Theme, no call-site changes.

import SwiftUI
import UIKit

@Observable
final class Palette {
    static let shared = Palette()

    enum Mode: String, CaseIterable { case system, light, dark }

    var accent: Color { didSet { Self.persist(accent) } }
    /// Theme mode. Default = follow the system. Light = SOPHIE hyperpop, Dark = goth-glass.
    var mode: Mode { didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey) } }
    /// The live system appearance, mirrored from the environment by the root view.
    var systemDark: Bool

    private init() {
        if let d = UserDefaults.standard.array(forKey: Self.key) as? [Double], d.count == 3 {
            accent = Color(red: d[0], green: d[1], blue: d[2])
        } else {
            accent = Palette.lavender
        }
        mode = Mode(rawValue: UserDefaults.standard.string(forKey: Self.modeKey) ?? "") ?? .system
        systemDark = UITraitCollection.current.userInterfaceStyle != .light
    }

    /// Is the effective theme light? (system mode resolves via `systemDark`)
    var resolvedLight: Bool {
        switch mode { case .light: return true; case .dark: return false; case .system: return !systemDark }
    }
    /// Forced color scheme, or nil in system mode (let iOS drive).
    var scheme: ColorScheme? {
        switch mode { case .light: return .light; case .dark: return .dark; case .system: return nil }
    }

    static let lavender = Color(red: 0.710, green: 0.659, blue: 1.0)   // #B5A8FF (default)

    /// Curated glass palette (name, color) shown as swatches in Settings.
    static let presets: [(name: String, color: Color)] = [
        ("Lavender", lavender),
        ("Ice",      Color(red: 0.51, green: 0.82, blue: 1.0)),
        ("Mint",     Color(red: 0.46, green: 0.90, blue: 0.70)),
        ("Ember",    Color(red: 1.0,  green: 0.66, blue: 0.46)),
        ("Rose",     Color(red: 1.0,  green: 0.55, blue: 0.72)),
        ("Gold",     Color(red: 1.0,  green: 0.80, blue: 0.42)),
    ]

    private static let key = "pms.accentRGB"
    private static let modeKey = "pms.lightMode"
    private static func persist(_ c: Color) {
        let u = UIColor(c); var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        u.getRed(&r, green: &g, blue: &b, alpha: &a)
        UserDefaults.standard.set([Double(r), Double(g), Double(b)], forKey: key)
    }

    /// A deeper, more saturated shade of any accent (gradients / pressed states).
    static func deepen(_ c: Color) -> Color {
        let u = UIColor(c); var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        u.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: Double(min(1, s + 0.12)), brightness: Double(b * 0.82))
    }

    /// Approximate equality so the selected swatch can show its ring.
    static func matches(_ a: Color, _ b: Color) -> Bool {
        let x = UIColor(a), y = UIColor(b)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        x.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        y.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return abs(r1 - r2) < 0.02 && abs(g1 - g2) < 0.02 && abs(b1 - b2) < 0.02
    }
}
