#!/usr/bin/env python3
"""Patch IconView.swift for orb backdrop + no-glyph mode.
- Adds orb-related properties (useOrbs, noGlyph, orbComposition, orbGround, orbColors)
- Replaces solid backdrop with PopMakerOrbs when ENCLAVE_ORBS=1
- Suppresses glyph rendering when ENCLAVE_NO_GLYPH=1
Additive + idempotent."""
import sys, pathlib

IV = "Sources/IconView.swift"
src = pathlib.Path(IV).read_text()

# ── 1. Add orb properties after usePopMakerGlyph ──
prop_anchor = (
    '    private let usePopMakerGlyph: Bool = {\n'
    '        ProcessInfo.processInfo.environment["ENCLAVE_PM_GLYPH"] == "1"\n'
    '    }()\n'
)
prop_new = prop_anchor + (
    '    private let useOrbs: Bool = {\n'
    '        ProcessInfo.processInfo.environment["ENCLAVE_ORBS"] == "1"\n'
    '    }()\n'
    '    private let noGlyph: Bool = {\n'
    '        ProcessInfo.processInfo.environment["ENCLAVE_NO_GLYPH"] == "1"\n'
    '    }()\n'
    '    private let orbComposition: PopMakerOrbs.Composition = {\n'
    '        let raw = ProcessInfo.processInfo.environment["ENCLAVE_ORB_COMP"] ?? "field"\n'
    '        return PopMakerOrbs.Composition(rawValue: raw) ?? .field\n'
    '    }()\n'
    '    private let orbGround: Color = {\n'
    '        if let hex = ProcessInfo.processInfo.environment["ENCLAVE_ORB_GROUND"],\n'
    '           let h = UInt(hex, radix: 16) { return Color(hex: h) }\n'
    '        return Color(red: 0.02, green: 0.02, blue: 0.02)\n'
    '    }()\n'
    '    private let orbColors: [Color] = {\n'
    '        let raw = ProcessInfo.processInfo.environment["ENCLAVE_ORB_COLORS"] ?? "B5A8FF,6B99FF,FFAE80"\n'
    '        return raw.split(separator: ",").compactMap { UInt($0, radix: 16).map { Color(hex: $0) } }\n'
    '    }()\n'
)
if "useOrbs" in src:
    print("  orb properties already present")
else:
    if prop_anchor not in src:
        sys.exit("ANCHOR (usePopMakerGlyph property) NOT FOUND")
    src = src.replace(prop_anchor, prop_new, 1)
    print("  added orb properties")

# ── 2. Replace backdrop with conditional orb rendering ──
backdrop_anchor = (
    '                // (A) vivid backdrop — gives the glass real content to refract\n'
    '                LinearGradient(colors: p.backdrop, startPoint: .top, endPoint: .bottom)\n'
)
backdrop_new = (
    '                // (A) vivid backdrop — gives the glass real content to refract\n'
    '                if useOrbs {\n'
    '                    PopMakerOrbs(composition: orbComposition, ground: orbGround, orbColors: orbColors)\n'
    '                } else {\n'
    '                    LinearGradient(colors: p.backdrop, startPoint: .top, endPoint: .bottom)\n'
    '                }\n'
)
if "PopMakerOrbs(composition:" in src:
    print("  orb backdrop already present")
else:
    if backdrop_anchor not in src:
        sys.exit("ANCHOR (backdrop LinearGradient) NOT FOUND")
    src = src.replace(backdrop_anchor, backdrop_new, 1)
    print("  patched backdrop")

# ── 3. Replace .background(LinearGradient...) with conditional ──
bg_anchor = '            .background(LinearGradient(colors: p.backdrop, startPoint: .top, endPoint: .bottom))\n'
bg_new = (
    '            .background {\n'
    '                if useOrbs { orbGround }\n'
    '                else { LinearGradient(colors: p.backdrop, startPoint: .top, endPoint: .bottom) }\n'
    '            }\n'
)
if ".background {" in src and "orbGround" in src:
    print("  background conditional already present")
else:
    if bg_anchor not in src:
        sys.exit("ANCHOR (.background LinearGradient) NOT FOUND")
    src = src.replace(bg_anchor, bg_new, 1)
    print("  patched background")

# ── 4. Add noGlyph suppression to the 3 glyph branches ──
# Pattern: replace "else if usePopMakerGlyph" with "else if !noGlyph && usePopMakerGlyph"
# and "else {\n                    EnclaveSlit" with "else if !noGlyph {\n                    EnclaveSlit"
# This appears 2x in stroke (flatGlass + flatGlassRing) and 1x in fill (liquidMark)

if "!noGlyph" in src:
    print("  noGlyph suppression already present")
else:
    # Replace "else if usePopMakerGlyph" → "else if !noGlyph && usePopMakerGlyph" (3 occurrences)
    old1 = "} else if usePopMakerGlyph {"
    new1 = "} else if !noGlyph && usePopMakerGlyph {"
    c1 = src.count(old1)
    if c1 != 3:
        sys.exit(f"Expected 3 usePopMakerGlyph branches, found {c1}")
    src = src.replace(old1, new1)
    print(f"  patched {c1} usePopMakerGlyph branches")

    # Replace "else {\n                    EnclaveSlit" → "else if !noGlyph {\n                    EnclaveSlit" (3 occurrences)
    old2 = "} else {\n                    EnclaveSlit"
    new2 = "} else if !noGlyph {\n                    EnclaveSlit"
    c2 = src.count(old2)
    if c2 != 3:
        sys.exit(f"Expected 3 EnclaveSlit else branches, found {c2}")
    src = src.replace(old2, new2)
    print(f"  patched {c2} EnclaveSlit else branches")

pathlib.Path(IV).write_text(src)
print("done")
