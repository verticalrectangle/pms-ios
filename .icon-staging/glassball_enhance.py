#!/usr/bin/env python3
"""Patch PopMakerOrbs.swift glassBall to add rim stroke + specular highlight
so the glass orbs read as physical glass objects on light ground."""
import pathlib, sys

P = "Sources/PopMakerOrbs.swift"
src = pathlib.Path(P).read_text()

old = (
    '    // iOS 26 Liquid Glass orb — frosted glass disc refracting the content behind\n'
    '    @ViewBuilder\n'
    '    private func glassBall(_ o: Orb, S: CGFloat) -> some View {\n'
    '        let size = S * o.size\n'
    '        Circle()\n'
    '            .fill(.white.opacity(0.001))\n'
    '            .glassEffect(glassTinted ? .regular.tint(o.color.opacity(0.35)) : .regular, in: .circle)\n'
    '            .frame(width: size, height: size)\n'
    '            .opacity(o.opacity)\n'
    '    }\n'
)
new = (
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
if "specular highlight" in src and "hairline rim" in src:
    print("  already patched")
else:
    if old not in src:
        sys.exit("ANCHOR NOT FOUND")
    src = src.replace(old, new, 1)
    pathlib.Path(P).write_text(src)
    print("  patched: glassBall enhanced with rim + specular")

print("done")
