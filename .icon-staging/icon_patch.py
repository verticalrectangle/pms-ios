#!/usr/bin/env python3
"""Additive patch: teach IconRenderer to build a solid-backdrop lens palette
from ENCLAVE_HEX/HEX2/GLYPH/INK env vars (PopMaker batch mode). Backward-
compatible: when ENCLAVE_HEX is absent the existing named-variant path is
unchanged. Idempotent."""
import sys, pathlib

def patch_once(path, old, new):
    src = pathlib.Path(path).read_text()
    marker = new.strip().splitlines()[0]
    if marker in src and old not in src:
        print(f"  already patched: {path}"); return
    if old not in src:
        sys.exit(f"ANCHOR NOT FOUND in {path} — aborting")
    if src.count(old) != 1:
        sys.exit(f"ANCHOR not unique in {path} ({src.count(old)}x) — aborting")
    pathlib.Path(path).write_text(src.replace(old, new, 1))
    print(f"  patched: {path}")

IV = "Sources/IconView.swift"
APP = "Sources/IconRendererApp.swift"

patch_once(IV,
    "    let variant: IconVariant\n    private var p: IconPalette { variant.palette }",
    "    let variant: IconVariant\n"
    "    private let paletteOverride: IconPalette?\n"
    "    init(variant: IconVariant) { self.variant = variant; self.paletteOverride = nil }\n"
    "    init(palette: IconPalette) { self.variant = .frostClear; self.paletteOverride = palette }\n"
    "    private var p: IconPalette { paletteOverride ?? variant.palette }")

patch_once(APP,
    "    private let variant: IconVariant = {\n"
    "        let raw = ProcessInfo.processInfo.environment[\"ENCLAVE_VARIANT\"] ?? IconVariant.allCases.first!.rawValue\n"
    "        return IconVariant(rawValue: raw) ?? .frostClear\n"
    "    }()\n"
    "    var body: some View { IconView(variant: variant) }",
    "    private let rootView: AnyView = {\n"
    "        let env = ProcessInfo.processInfo.environment\n"
    "        // PopMaker batch mode: solid backdrop + lens + glass glyph, driven by env\n"
    "        // (see capture_pms.sh). Falls back to the named-variant path otherwise.\n"
    "        if let hex = env[\"ENCLAVE_HEX\"], let h1 = UInt(hex, radix: 16) {\n"
    "            let h2 = env[\"ENCLAVE_HEX2\"].flatMap { UInt($0, radix: 16) } ?? h1\n"
    "            let glyph: GlyphMode\n"
    "            switch env[\"ENCLAVE_GLYPH\"] ?? \"liquidMark\" {\n"
    "            case \"flatGlass\":     glyph = .flatGlass\n"
    "            case \"flatGlassRing\": glyph = .flatGlassRing\n"
    "            default:              glyph = .liquidMark\n"
    "            }\n"
    "            let ink = env[\"ENCLAVE_INK\"].flatMap { UInt($0, radix: 16) }.map { Color(hex: $0) } ?? Color.white\n"
    "            return AnyView(IconView(palette: .init(\n"
    "                backdrop: [Color(hex: h1), Color(hex: h2)], blooms: [], glass: .clear, tint: nil,\n"
    "                glassMode: .lens, glyphMode: glyph, ink: ink, coreShadow: 0, shimmer: false)))\n"
    "        }\n"
    "        let raw = env[\"ENCLAVE_VARIANT\"] ?? IconVariant.allCases.first!.rawValue\n"
    "        return AnyView(IconView(variant: IconVariant(rawValue: raw) ?? .frostClear))\n"
    "    }()\n"
    "    var body: some View { rootView }")

print("done")
