#!/usr/bin/env python3
"""Patch PopMakerOrbs.swift glassBall to render non-see-through glass orbs
matching the iOS 26 stock icon material: solid frosted glass body with
internal diffusion, convex gloss, bright rim, specular glint."""
import pathlib, sys

P = "Sources/PopMakerOrbs.swift"
src = pathlib.Path(P).read_text()

old = (
    '    // iOS 26 Liquid Glass orb — frosted glass disc refracting the content behind.\n'
    '    // Rim + specular highlight added so the glass reads on light ground (where\n'
    '    // .glassEffect alone is too subtle — it needs dark/colorful content to refract).\n'
    '    @ViewBuilder\n'
    '    private func glassBall(_ o: Orb, S: CGFloat) -> some View {\n'
    '        let size = S * o.size\n'
    '        Circle()\n'
    '            .fill(.white.opacity(0.001))\n'
    '            .glassEffect(glassTinted ? .regular.tint(o.color.opacity(0.40)) : .regular, in: .circle)\n'
    '            // specular highlight (top-left) — the glass glint that reads as a physical object\n'
    '            .overlay(alignment: .topLeading) {\n'
    '                Circle()\n'
    '                    .fill(RadialGradient(colors: [.white.opacity(0.60), .white.opacity(0)],\n'
    '                                         center: .center, startRadius: 0, endRadius: size * 0.18))\n'
    '                    .frame(width: size * 0.35, height: size * 0.35)\n'
    '                    .offset(x: size * 0.12, y: size * 0.08)\n'
    '            }\n'
    '            // hairline rim — defines the glass edge against the ground\n'
    '            .overlay { Circle().strokeBorder(.white.opacity(0.50), lineWidth: S * 0.003) }\n'
    '            .frame(width: size, height: size)\n'
    '            .opacity(o.opacity)\n'
    '    }\n'
)
new = (
    '    // Non-see-through glass orb — the iOS 26 stock icon material language:\n'
    '    // solid frosted glass body (.glassEffect as the primary fill, not a thin\n'
    '    // overlay), convex gloss gradient, bright rim, specular glint. The tint\n'
    '    // provides the color identity; the glass provides the material.\n'
    '    @ViewBuilder\n'
    '    private func glassBall(_ o: Orb, S: CGFloat) -> some View {\n'
    '        let size = S * o.size\n'
    '        let tint = glassTinted ? o.color.opacity(0.55) : Color.white.opacity(0.12)\n'
    '        Circle()\n'
    '            .fill(.white.opacity(0.001))\n'
    '            .glassEffect(.regular.tint(tint), in: .circle)\n'
    '            // convex face gloss — top-to-bottom sheen that reads as glass volume\n'
    '            .overlay {\n'
    '                LinearGradient(colors: [.white.opacity(0.35), .clear, .black.opacity(0.08)],\n'
    '                               startPoint: .top, endPoint: .bottom)\n'
    '                    .clipShape(Circle())\n'
    '                    .blendMode(.overlay)\n'
    '            }\n'
    '            // specular glint (top-left) — the bright glass reflection\n'
    '            .overlay(alignment: .topLeading) {\n'
    '                Circle()\n'
    '                    .fill(RadialGradient(colors: [.white.opacity(0.85), .white.opacity(0)],\n'
    '                                         center: .center, startRadius: 0, endRadius: size * 0.16))\n'
    '                    .frame(width: size * 0.32, height: size * 0.32)\n'
    '                    .offset(x: size * 0.14, y: size * 0.10)\n'
    '            }\n'
    '            // bright rim — the glass edge, thicker than a hairline\n'
    '            .overlay { Circle().strokeBorder(.white.opacity(0.70), lineWidth: S * 0.004) }\n'
    '            // inner depth shadow at the bottom edge\n'
    '            .overlay {\n'
    '                Circle().strokeBorder(\n'
    '                    LinearGradient(colors: [.clear, .black.opacity(0.20)],\n'
    '                                   startPoint: .center, endPoint: .bottom),\n'
    '                    lineWidth: S * 0.006)\n'
    '            }\n'
    '            .frame(width: size, height: size)\n'
    '            .shadow(color: .black.opacity(0.15), radius: S * 0.008, x: 0, y: S * 0.005)\n'
    '            .opacity(o.opacity)\n'
    '    }\n'
)
if "convex face gloss" in src:
    print("  already patched")
else:
    if old not in src:
        sys.exit("ANCHOR NOT FOUND")
    src = src.replace(old, new, 1)
    pathlib.Path(P).write_text(src)
    print("  patched: glassBall rewritten as iOS 26 stock glass material")

print("done")
