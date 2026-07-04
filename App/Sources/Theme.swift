//  Theme.swift
//  Pop Maker Studio — design tokens ported from the "Goth Frutiger Aero" glass UI.
//  White-on-black, hairline alpha-white depth, one rationed accent — now LAVENDER.
//
//  Everything visual keys off `Theme`. Glass is a Material + gloss overlay + hairline
//  stroke, applied via `.glass()`. No drop shadows on chrome; depth is borders + alpha.

import SwiftUI

enum Theme {

    // ── Theme mode. Dark = goth-glass (default). Light = SOPHIE hyperpop. ──
    // All tokens are computed off Palette so a mode/accent change re-tints the
    // whole UI reactively (Observation tracks the access through these getters).
    static var light: Bool { Palette.shared.resolvedLight }

    // ── Accent — user-selectable, persisted. ──
    static var accent     : Color { Palette.shared.accent }
    static var accentDeep : Color { Palette.deepen(Palette.shared.accent) }
    static func accentA(_ a: Double) -> Color { accent.opacity(a) }

    // ── Ground / figure (ink = the figure color; text/lines derive from it) ──
    static var ground   : Color { light ? Color(red: 0.95, green: 0.955, blue: 0.97) : Color(red: 0.02, green: 0.02, blue: 0.02) }
    static var ink      : Color { light ? Color(red: 0.06, green: 0.06, blue: 0.10) : .white }

    // ── Hairline ramp — alpha over the ink color (dark-on-light / light-on-dark) ──
    static var lineFaint  : Color { ink.opacity(0.06) }
    static var line       : Color { ink.opacity(light ? 0.12 : 0.15) }
    static var lineStrong : Color { ink.opacity(light ? 0.18 : 0.22) }
    static var lineHover  : Color { ink.opacity(0.50) }

    static var txt      : Color { ink }
    static var txtBody  : Color { ink.opacity(0.80) }
    static var txtMuted : Color { ink.opacity(light ? 0.55 : 0.58) }
    static var txtLabel : Color { ink.opacity(0.40) }
    static var txtGhost : Color { ink.opacity(0.25) }

    // ── Brick scope colors ──
    static let glassCyan = Color(red: 0.51, green: 0.82, blue: 1.0)       // clip-bound glass FX
    static let bodyViolet = Color(red: 0.78, green: 0.62, blue: 1.0)      // body/silhouette FX

    // ── Radii — brand is rectangles; corners are small, never pills except controls ──
    static let rSheet: CGFloat = 26
    static let rCard: CGFloat  = 16
    static let rTile: CGFloat  = 12
    static let rBrick: CGFloat = 6
}

// MARK: - Type

extension Font {
    /// Display / wordmark — Inter Black, tight, uppercase at call site.
    static func disp(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: .default) }
    /// Structural label — heavy, wide-tracked, uppercase at call site.
    static func label(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .default) }
    /// Tabular numerics for timecode / meters.
    static func num(_ size: CGFloat, _ w: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: w, design: .default).monospacedDigit()
    }
}

// MARK: - Glass material

/// The core surface. `.ultraThinMaterial` for the frost, a top-third gloss for the
/// Frutiger-Aero wet look, and a hairline stroke for edge definition.
struct Glass: ViewModifier {
    var radius: CGFloat = Theme.rCard
    var flat: Bool = false          // dense-data surfaces get less gloss
    var active: Bool = false        // "live" lavender ring
    var sheer: Bool = false         // thinner frost — the atmosphere glows through (depth)

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(sheer ? 0.28 : 1.0)   // thin the frost so the bokeh reads through
                    // wet top-third reflection
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(flat ? 0.06 : 0.16), .clear],
                                startPoint: .top, endPoint: .center)
                        )
                        .allowsHitTesting(false)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        active ? Theme.accentA(0.55) : Theme.ink.opacity(flat ? 0.12 : 0.16),
                        lineWidth: 1)
            )
            .overlay(alignment: .top) {
                // bright top rim — the light-catch on real frosted acrylic
                if sheer {
                    UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom),
                            lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                // active "bioluminescent" bloom
                if active {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Theme.accentA(0.28), lineWidth: 3).blur(radius: 6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            // SOPHIE mode: soft drop shadow so panels read as glossy objects on white.
            .shadow(color: Theme.light ? Color.black.opacity(0.10) : .clear,
                    radius: 16, x: 0, y: 9)
    }
}

extension View {
    func glass(_ radius: CGFloat = Theme.rCard, flat: Bool = false, active: Bool = false, sheer: Bool = false) -> some View {
        modifier(Glass(radius: radius, flat: flat, active: active, sheer: sheer))
    }

    /// Press feedback matching the HTML: compress + brighten, no glow.
    func pressable() -> some View { buttonStyle(GlassPressStyle()) }
}

struct GlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Atmosphere (dark goth-aero backdrop + drifting bokeh)

struct AtmosphereView: View {
    @State private var drift = false

    // A bokeh orb: normalized position, size, blur (far = big+soft, near = small+
    // tight-cored), a luminous core + halo, and a slow drift. Varied blur is what
    // the eye reads as depth.
    private struct Orb {
        let nx, ny, size, blur, opacity, dy: CGFloat
        let core, halo: Color
    }
    private static let lav = Palette.lavender
    private static let blu = Color(red: 0.42, green: 0.60, blue: 1.0)   // cool
    private static let emb = Color(red: 1.0,  green: 0.68, blue: 0.50)  // warm ember
    // SOPHIE candy palette (glossy plastic hues) for the light theme
    private static let pink = Color(red: 1.0,  green: 0.36, blue: 0.66)
    private static let cblu = Color(red: 0.29, green: 0.42, blue: 1.0)
    private static let cpur = Color(red: 0.66, green: 0.36, blue: 1.0)

    // Dark: lavender/blue/ember glossy spheres — a few in focus, the rest bokeh.
    private let orbs: [Orb] = [
        Orb(nx: 0.14, ny: 0.15, size: 330, blur: 52, opacity: 0.50, dy:  34, core: lav, halo: lav),
        Orb(nx: 0.90, ny: 0.74, size: 400, blur: 66, opacity: 0.40, dy: -42, core: blu, halo: blu),
        Orb(nx: 0.52, ny: 0.48, size: 200, blur: 40, opacity: 0.30, dy:  16, core: lav, halo: lav),
        Orb(nx: 0.86, ny: 0.13, size: 112, blur: 1,  opacity: 0.95, dy:  22, core: lav, halo: lav),   // in focus
        Orb(nx: 0.15, ny: 0.52, size: 88,  blur: 1,  opacity: 0.92, dy: -16, core: blu, halo: blu),   // in focus
        Orb(nx: 0.91, ny: 0.55, size: 64,  blur: 2,  opacity: 0.94, dy:  24, core: emb, halo: emb),   // in focus
    ]

    // SOPHIE light: punchy glossy candy spheres, strong DOF — crisp heroes + soft bokeh.
    private let lightOrbs: [Orb] = [
        Orb(nx: 0.20, ny: 0.14, size: 340, blur: 58, opacity: 0.48, dy:  30, core: pink, halo: pink),
        Orb(nx: 0.82, ny: 0.82, size: 400, blur: 72, opacity: 0.42, dy: -38, core: cblu, halo: cblu),
        Orb(nx: 0.56, ny: 0.54, size: 210, blur: 42, opacity: 0.42, dy:  18, core: cpur, halo: cpur),
        Orb(nx: 0.88, ny: 0.12, size: 132, blur: 1,  opacity: 0.98, dy:  22, core: pink, halo: pink),  // in focus
        Orb(nx: 0.11, ny: 0.47, size: 104, blur: 1,  opacity: 0.96, dy: -16, core: cblu, halo: cblu),  // in focus
        Orb(nx: 0.91, ny: 0.55, size: 84,  blur: 2,  opacity: 0.95, dy:  24, core: cpur, halo: cpur),  // in focus
        Orb(nx: 0.31, ny: 0.83, size: 62,  blur: 1,  opacity: 0.95, dy: -12, core: pink, halo: pink),  // in focus
    ]

    // A glossy 3D sphere: lit top-left (bright desaturated highlight → body → dark
    // saturated terminator) + a crisp specular. Blur it and the SAME ball reads as
    // soft bokeh — that variance IS the depth of field.
    @ViewBuilder private func ball(_ o: Orb) -> some View {
        Circle()
            .fill(RadialGradient(
                colors: [o.core.shade(1.7), o.core, o.core.shade(0.45)],
                center: UnitPoint(x: 0.36, y: 0.30),
                startRadius: o.size * 0.02, endRadius: o.size * 0.62))
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.95), .white.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: o.size * 0.12))
                    .frame(width: o.size * 0.32, height: o.size * 0.32)
                    .offset(x: o.size * 0.14, y: o.size * 0.10)
            }
            .frame(width: o.size, height: o.size)
            .blur(radius: o.blur)      // ≤2 = glossy in-focus ball; high = soft bokeh
            .opacity(o.opacity)
    }

    var body: some View {
        let lightMode = Theme.light
        return GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Theme.ground
                if lightMode {
                    RadialGradient(colors: [Self.pink.opacity(0.09), .clear],
                                   center: .topLeading, startRadius: 0, endRadius: 560)
                    RadialGradient(colors: [Self.cblu.opacity(0.09), .clear],
                                   center: .bottomTrailing, startRadius: 0, endRadius: 520)
                } else {
                    RadialGradient(colors: [Theme.accentA(0.12), .clear],
                                   center: .topLeading, startRadius: 0, endRadius: 540)
                    RadialGradient(colors: [Self.blu.opacity(0.09), .clear],
                                   center: .bottomTrailing, startRadius: 0, endRadius: 500)
                }
                ForEach(Array((lightMode ? lightOrbs : orbs).enumerated()), id: \.offset) { i, o in
                    ball(o)
                        .position(x: o.nx * w, y: o.ny * h + (drift ? o.dy : -o.dy))
                        .animation(.easeInOut(duration: 24 + Double(i) * 2.5)
                            .repeatForever(autoreverses: true), value: drift)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { drift = true }
    }
}
