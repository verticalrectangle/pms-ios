#!/usr/bin/env python3
"""Patch IconRendererApp.swift to handle the ENCLAVE_ORBS path.
When ENCLAVE_ORBS=1, create an IconView(palette:) with a lens palette so the
orb properties inside IconView are used. Without this, the orb path falls
through to the default named variant."""
import pathlib

APP = "Sources/IconRendererApp.swift"
src = pathlib.Path(APP).read_text()

if "ENCLAVE_ORBS" in src:
    print("  already patched for orbs")
else:
    # Insert orb path before the ENCLAVE_HEX check
    old = '        // PopMaker batch mode: solid backdrop + lens + glass glyph, driven by env\n'
    new = (
        '        // PopMaker orb mode: orbs as backdrop, lens glass on top\n'
        '        if env["ENCLAVE_ORBS"] == "1" {\n'
        '            let glyph: GlyphMode\n'
        '            switch env["ENCLAVE_GLYPH"] ?? "liquidMark" {\n'
        '            case "flatGlass":     glyph = .flatGlass\n'
        '            case "flatGlassRing": glyph = .flatGlassRing\n'
        '            default:              glyph = .liquidMark\n'
        '            }\n'
        '            let ink = env["ENCLAVE_INK"].flatMap { UInt($0, radix: 16) }.map { Color(hex: $0) } ?? Color.white\n'
        '            // backdrop is a placeholder — the orb view replaces it inside IconView body\n'
        '            return AnyView(IconView(palette: .init(\n'
        '                backdrop: [.black, .black], blooms: [], glass: .clear, tint: nil,\n'
        '                glassMode: .lens, glyphMode: glyph, ink: ink, coreShadow: 0, shimmer: false)))\n'
        '        }\n'
        '        // PopMaker batch mode: solid backdrop + lens + glass glyph, driven by env\n'
    )
    if old not in src:
        import sys; sys.exit("ANCHOR NOT FOUND")
    src = src.replace(old, new, 1)
    pathlib.Path(APP).write_text(src)
    print("  patched: orb path added")

print("done")
