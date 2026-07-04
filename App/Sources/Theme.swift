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

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)
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
    func glass(_ radius: CGFloat = Theme.rCard, flat: Bool = false, active: Bool = false) -> some View {
        modifier(Glass(radius: radius, flat: flat, active: active))
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
    var body: some View {
        ZStack {
            Theme.ground
            RadialGradient(colors: [.white.opacity(0.05), .clear],
                           center: .top, startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Theme.accentA(0.10), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 380)
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(RadialGradient(
                        colors: [.white.opacity(0.10), Theme.accentA(0.06), .clear],
                        center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 120))
                    .frame(width: [150, 90, 200, 70][i], height: [150, 90, 200, 70][i])
                    .offset(x: [-60, 150, 170, -110][i], y: drift ? [-120, 40, 260, -40][i] : [-90, 90, 300, 0][i])
                    .blur(radius: 2)
                    .opacity(0.5)
                    .animation(.easeInOut(duration: 26).repeatForever(autoreverses: true).delay(Double(i) * 2), value: drift)
            }
        }
        .ignoresSafeArea()
        .onAppear { drift = true }
    }
}
