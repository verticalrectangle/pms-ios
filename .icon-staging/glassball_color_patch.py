#!/usr/bin/env python3
"""Patch glassBall: add a colored fill layer behind the glass so the hue reads
on light ground. Bump tint opacity. For untinted variants, use a subtle
colored fill from the orb's own hue at low opacity so they're not white."""
import pathlib, sys

P = "Sources/PopMakerOrbs.swift"
src = pathlib.Path(P).read_text()

old = (
    '    @ViewBuilder\n'
    '    private func glassBall(_ o: Orb, S: CGFloat) -> some View {\n'
    '        let size = S * o.size\n'
    '        let tint = glassTinted ? o.color.opacity(0.55) : Color.white.opacity(0.12)\n'
    '        Circle()\n'
    '            .fill(.white.opacity(0.001))\n'
    '            .glassEffect(.regular.tint(tint), in: .circle)\n'
)
new = (
    '    @ViewBuilder\n'
    '    private func glassBall(_ o: Orb, S: CGFloat) -> some View {\n'
    '        let size = S * o.size\n'
    '        let tint = glassTinted ? o.color.opacity(0.70) : o.color.opacity(0.30)\n'
    '        Circle()\n'
    '            // colored fill behind the glass so the hue reads on light ground\n'
    '            .fill(o.color.opacity(glassTinted ? 0.45 : 0.20))\n'
    '            .glassEffect(.regular.tint(tint), in: .circle)\n'
)
if "colored fill behind" in src:
    print("  already patched")
else:
    if old not in src:
        sys.exit("ANCHOR NOT FOUND")
    src = src.replace(old, new, 1)
    pathlib.Path(P).write_text(src)
    print("  patched: glassBall now has colored fill + stronger tint")

print("done")
