extension Color {
    /// Brightness-scaled shade for sphere shading. f>1 → lighter + desaturated
    /// (the lit highlight side); f<1 → darker + more saturated (the shadow side).
    /// Ported from Palette.swift so the orbs match the app's ball() rendering.
    func shade(_ f: Double) -> Color {
        let u = UIColor(self); var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        u.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h),
                     saturation: Double(max(0, min(1, s * (f > 1 ? 0.62 : 1.18)))),
                     brightness: Double(max(0, min(1, b * f))),
                     opacity: Double(a))
    }
}

//  PopMakerOrbs.swift
//  The AtmosphereView bokeh orbs, repurposed as icon backdrop content.
//  Renders the exact same glossy 3D spheres from Theme.swift — RadialGradient
//  lit top-left + specular highlight + depth blur — in three compositions:
//  .field (7 orbs at UI positions), .cluster (5 orbs, tight), .hero (1 large).
//  Driven by env vars so capture_pms.sh can parameterize per variant.

import SwiftUI

struct PopMakerOrbs: View {
    enum Composition: String {
        case field, cluster, hero
    }

    let composition: Composition
    let ground: Color
    let orbColors: [Color]      // 1–3 hues; extras cycle

    private struct Orb {
        let nx, ny, size, blur, opacity: CGFloat
        let color: Color
    }

    private var orbs: [Orb] {
        let cols = orbColors
        func c(_ i: Int) -> Color { cols[i % cols.count] }

        switch composition {
        case .field:
            // Exact AtmosphereView positions/sizes/blur/opacity — 7 orbs
            return [
                Orb(nx: 0.91, ny: 0.16, size: 0.34, blur: 0.004, opacity: 0.95, color: c(0)),
                Orb(nx: 0.08, ny: 0.71, size: 0.30, blur: 0.006, opacity: 0.93, color: c(1 % cols.count)),
                Orb(nx: 0.74, ny: 0.87, size: 0.25, blur: 0.016, opacity: 0.79, color: c(2 % cols.count)),
                Orb(nx: 0.29, ny: 0.29, size: 0.20, blur: 0.014, opacity: 0.75, color: c(0)),
                Orb(nx: 0.52, ny: 0.51, size: 0.14, blur: 0.060, opacity: 0.55, color: c(1 % cols.count)),
                Orb(nx: 0.86, ny: 0.50, size: 0.11, blur: 0.068, opacity: 0.51, color: c(0)),
                Orb(nx: 0.20, ny: 0.16, size: 0.12, blur: 0.060, opacity: 0.51, color: c(2 % cols.count)),
            ]
        case .cluster:
            // 5 orbs, tighter around center — reads at icon scale
            return [
                Orb(nx: 0.50, ny: 0.42, size: 0.38, blur: 0.003, opacity: 0.96, color: c(0)),
                Orb(nx: 0.22, ny: 0.62, size: 0.26, blur: 0.010, opacity: 0.88, color: c(1 % cols.count)),
                Orb(nx: 0.78, ny: 0.58, size: 0.22, blur: 0.014, opacity: 0.82, color: c(2 % cols.count)),
                Orb(nx: 0.38, ny: 0.82, size: 0.16, blur: 0.030, opacity: 0.65, color: c(0)),
                Orb(nx: 0.66, ny: 0.22, size: 0.14, blur: 0.036, opacity: 0.58, color: c(1 % cols.count)),
            ]
        case .hero:
            // Single large glossy sphere, optically centered
            return [
                Orb(nx: 0.50, ny: 0.50, size: 0.62, blur: 0.002, opacity: 0.98, color: c(0)),
            ]
        }
    }

    var body: some View {
        GeometryReader { geo in
            let S = min(geo.size.width, geo.size.height)
            ZStack {
                ground
                ForEach(Array(orbs.enumerated()), id: \.offset) { _, o in
                    ball(o, S: S)
                        .position(x: o.nx * S, y: o.ny * S)
                }
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func ball(_ o: Orb, S: CGFloat) -> some View {
        let size = S * o.size
        Circle()
            .fill(RadialGradient(
                colors: [o.color.shade(1.7), o.color, o.color.shade(0.45)],
                center: UnitPoint(x: 0.36, y: 0.30),
                startRadius: size * 0.02, endRadius: size * 0.62))
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.95), .white.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: size * 0.12))
                    .frame(width: size * 0.32, height: size * 0.32)
                    .offset(x: size * 0.14, y: size * 0.10)
            }
            .frame(width: size, height: size)
            .blur(radius: S * o.blur)
            .opacity(o.opacity)
    }
}
