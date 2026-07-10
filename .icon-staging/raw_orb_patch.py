#!/usr/bin/env python3
"""Patch IconView.swift: suppress markLayer entirely when useOrbs && noGlyph.
This removes the glass disc + glyph so raw orbs fill the tile alone."""
import pathlib, sys

IV = "Sources/IconView.swift"
src = pathlib.Path(IV).read_text()

old = "                    // lens mode: no pane; the glyph disc is the only glass element\n                    if p.shimmer { opticalOverlays(shape: shape, S: S) }\n                    markLayer(S: S)\n"
new = "                    // lens mode: no pane; the glyph disc is the only glass element\n                    // (raw orb mode: suppress disc + glyph entirely)\n                    if p.shimmer { opticalOverlays(shape: shape, S: S) }\n                    if !(useOrbs && noGlyph) { markLayer(S: S) }\n"

if "!(useOrbs && noGlyph)" in src:
    print("  already patched")
else:
    if old not in src:
        sys.exit("ANCHOR NOT FOUND")
    src = src.replace(old, new, 1)
    pathlib.Path(IV).write_text(src)
    print("  patched: markLayer suppressed for raw orb mode")

print("done")
