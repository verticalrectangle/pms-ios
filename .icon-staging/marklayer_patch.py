#!/usr/bin/env python3
"""Patch IconView.swift markLayer to use PopMakerGlyph (play triangle) when
ENCLAVE_PM_GLYPH=1 is set. Additive + idempotent — the Enclave path is preserved
as the else branch."""
import sys, pathlib

IV = "Sources/IconView.swift"
src = pathlib.Path(IV).read_text()

# 1. Add usePopMakerGlyph property after split property
prop_anchor = '    private let split: CGFloat = {\n        CGFloat(Double(ProcessInfo.processInfo.environment["ENCLAVE_SPLIT"] ?? "0") ?? 0)\n    }()\n'
prop_new = prop_anchor + '    private let usePopMakerGlyph: Bool = {\n        ProcessInfo.processInfo.environment["ENCLAVE_PM_GLYPH"] == "1"\n    }()\n'
if "usePopMakerGlyph" in src:
    print("  usePopMakerGlyph already present")
else:
    if prop_anchor not in src:
        sys.exit("ANCHOR (split property) NOT FOUND")
    src = src.replace(prop_anchor, prop_new, 1)
    print("  added usePopMakerGlyph property")

# 2. Replace EnclaveSlit stroke in flatGlass + flatGlassRing (2 occurrences)
stroke_old = (
    '                } else {\n'
    '                    EnclaveSlit(open: 1)\n'
    '                        .stroke(slitStroke(),\n'
    '                                style: StrokeStyle(lineWidth: S * 0.06,\n'
    '                                                    lineCap: .round, lineJoin: .round))\n'
    '                }'
)
stroke_new = (
    '                } else if usePopMakerGlyph {\n'
    '                    PopMakerGlyph()\n'
    '                        .stroke(slitStroke(),\n'
    '                                style: StrokeStyle(lineWidth: S * 0.06,\n'
    '                                                    lineCap: .round, lineJoin: .round))\n'
    '                } else {\n'
    '                    EnclaveSlit(open: 1)\n'
    '                        .stroke(slitStroke(),\n'
    '                                style: StrokeStyle(lineWidth: S * 0.06,\n'
    '                                                    lineCap: .round, lineJoin: .round))\n'
    '                }'
)
if "PopMakerGlyph()" in src:
    print("  PopMakerGlyph branches already present")
else:
    count = src.count(stroke_old)
    if count != 2:
        sys.exit(f"Expected 2 stroke anchors, found {count}")
    src = src.replace(stroke_old, stroke_new)
    print(f"  patched {count} stroke branches")

    # 3. Replace EnclaveSlit fill in liquidMark (1 occurrence)
    fill_old = (
        '                } else {\n'
        '                    EnclaveSlit(open: 1)\n'
        '                        .fill(.white.opacity(0.001))\n'
        '                        .glassEffect(.regular, in: EnclaveSlit(open: 1))\n'
        '                }'
    )
    fill_new = (
        '                } else if usePopMakerGlyph {\n'
        '                    PopMakerGlyph()\n'
        '                        .fill(.white.opacity(0.001))\n'
        '                        .glassEffect(.regular, in: PopMakerGlyph())\n'
        '                } else {\n'
        '                    EnclaveSlit(open: 1)\n'
        '                        .fill(.white.opacity(0.001))\n'
        '                        .glassEffect(.regular, in: EnclaveSlit(open: 1))\n'
        '                }'
    )
    count = src.count(fill_old)
    if count != 1:
        sys.exit(f"Expected 1 fill anchor, found {count}")
    src = src.replace(fill_old, fill_new, 1)
    print("  patched 1 fill branch")

pathlib.Path(IV).write_text(src)
print("done")
