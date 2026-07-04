//  Theme.swift
//  Pop Maker Studio — design tokens ported from the "Goth Frutiger Aero" glass UI.
//  White-on-black, hairline alpha-white depth, one rationed accent — now LAVENDER.
//
//  Everything visual keys off `Theme`. Glass is a Material + gloss overlay + hairline
//  stroke, applied via `.glass()`. No drop shadows on chrome; depth is borders + alpha.

import SwiftUI

enum Theme {

    // ── Accent (was amber; now lavender). Rationed to "live"/active + screen voice. ──
    static let accent      = Color(red: 0.710, green: 0.659, blue: 1.0)   // #B5A8FF
    static let accentDeep  = Color(red: 0.545, green: 0.478, blue: 0.94)  // #8B7AF0
    static func accentA(_ a: Double) -> Color { accent.opacity(a) }

    // ── Ground / figure ──
    static let ground   = Color(red: 0.02, green: 0.02, blue: 0.02)       // #050505
    static let ink      = Color.white

    // ── Alpha-white ramp (greys don't exist as hues) ──
    static let lineFaint  = Color.white.opacity(0.06)
    static let line       = Color.white.opacity(0.15)
    static let lineStrong = Color.white.opacity(0.22)
    static let lineHover  = Color.white.opacity(0.50)

    static let txt      = Color.white
    static let txtBody  = Color.white.opacity(0.80)
    static let txtMuted = Color.white.opacity(0.58)
    static let txtLabel = Color.white.opacity(0.40)
    static let txtGhost = Color.white.opacity(0.25)

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
                        .opacity(sheer ? 0.5 : 1.0)   // a pane you look THROUGH, not a wall
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
                        active ? Theme.accentA(0.55) : Color.white.opacity(flat ? 0.12 : 0.16),
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
    private static let lav = Theme.accent
    private static let blu = Color(red: 0.42, green: 0.60, blue: 1.0)   // cool
    private static let emb = Color(red: 1.0,  green: 0.68, blue: 0.50)  // warm ember

    private let orbs: [Orb] = [
        // FAR — large, very soft, ambient
        Orb(nx: 0.10, ny: 0.15, size: 340, blur: 50, opacity: 0.55, dy:  34, core: lav,    halo: lav),
        Orb(nx: 0.90, ny: 0.70, size: 420, blur: 60, opacity: 0.42, dy: -42, core: blu,    halo: blu),
        // MID
        Orb(nx: 0.82, ny: 0.19, size: 190, blur: 28, opacity: 0.60, dy:  26, core: lav,    halo: lav),
        Orb(nx: 0.13, ny: 0.60, size: 168, blur: 24, opacity: 0.50, dy: -22, core: blu,    halo: blu),
        // NEAR — small, tight bright cores (these are the "pop")
        Orb(nx: 0.29, ny: 0.31, size: 82,  blur: 10, opacity: 0.90, dy:  18, core: .white, halo: lav),
        Orb(nx: 0.66, ny: 0.85, size: 58,  blur: 8,  opacity: 0.75, dy: -14, core: emb,    halo: emb),
        Orb(nx: 0.93, ny: 0.11, size: 44,  blur: 7,  opacity: 0.78, dy:  15, core: .white, halo: lav),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Theme.ground
                RadialGradient(colors: [Theme.accentA(0.12), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 540)
                RadialGradient(colors: [Self.blu.opacity(0.09), .clear],
                               center: .bottomTrailing, startRadius: 0, endRadius: 500)
                ForEach(Array(orbs.enumerated()), id: \.offset) { i, o in
                    Circle()
                        .fill(RadialGradient(
                            colors: [o.core.opacity(0.85), o.halo.opacity(0.42), .clear],
                            center: .center, startRadius: 0, endRadius: o.size * 0.5))
                        .frame(width: o.size, height: o.size)
                        .blur(radius: o.blur)
                        .opacity(o.opacity)
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
