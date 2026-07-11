#!/usr/bin/env python3
"""Validate the pms-ios makeup catalog and asset contract.

This is a deterministic standalone check that parses the Swift catalog files
and decodes every bundled makeup PNG. It does not require building the app or
importing Swift. It targets the final shared worktree after the Stage 5
updates from docs/MAKEUP_REALISM_PLAN.md:

* 35 Makeup rail presets in App/Sources/FilterLooks.swift
* exactly the 20 new look IDs from the plan
* every face_fx makeupTex references a bundled 1024x1024 RGBA PNG
    * every generated plate is exposed in App/Sources/MakeupStudio.swift
* alpha coverage is neither zero nor full
* the inner mouth seam stays meaningfully transparent

Return code: 0 for a finished catalog, non-zero for any missing/malformed/
unwired asset or catalog mismatch.

Limitations (this tool is not a Swift compiler):
- It parses the Swift source structurally. It does not execute the Swift code.
- The legacy douyin plate (makeup_douyin.png) is treated as the standalone
  non-generated plate because it is the "douyin classic" referenced separately
  from the tools/gen_makeup_elements.py variant factory.
- The mouth-seam polygon is the canonical MediaPipe inner lip contour at
  1024x1024 UV space; it is checked for mean alpha, not per-look semantics.
"""
import argparse
import os
import re
import sys

try:
    from PIL import Image, ImageDraw, ImageStat
except ImportError as exc:  # pragma: no cover
    print(f"ERROR: Pillow is required to decode PNGs ({exc})", file=sys.stderr)
    sys.exit(2)

REPO_ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
PLAN_PATH = os.path.join(REPO_ROOT, "docs", "MAKEUP_REALISM_PLAN.md")
FILTER_LOOKS_PATH = os.path.join(REPO_ROOT, "App", "Sources", "FilterLooks.swift")
MAKEUP_STUDIO_PATH = os.path.join(REPO_ROOT, "App", "Sources", "MakeupStudio.swift")
ASSETS_DIR = os.path.join(REPO_ROOT, "Engine", "EngineAssets", "models", "face")

SZ = 1024

# Canonical MediaPipe inner lip contour (1024x1024 UV space) used by the
# generator and the standalone douyin painter to clear the mouth opening.
MOUTH_INNER = [
    (413.316096, 710.607872), (423.307264, 708.982784), (441.505792, 708.982784),
    (463.034368, 708.982784), (486.796288, 708.982784), (512.023552, 708.964352),
    (537.203712, 708.982784), (560.965632, 708.982784), (582.494208, 708.982784),
    (600.692736, 708.982784), (610.683904, 710.607872), (600.8832, 712.0896),
    (585.787392, 711.9646720000001), (564.570112, 711.9646720000001),
    (539.614208, 711.9646720000001), (511.976448, 711.9646720000001),
    (484.385792, 711.9646720000001), (459.429888, 711.9646720000001),
    (438.212608, 711.9646720000001), (423.1168, 712.0896),
]

MOUTH_MEAN_MAX = 80.0
MOUTH_MAX_MAX = 150

# Legacy standalone plate; now generated alongside the other plates in
# gen_makeup_elements.py. Kept as a doc comment for history.
# DOUYIN_PNG = "makeup_douyin.png"


def error(errors, msg):
    errors.append(msg)
    print(f"FAIL: {msg}", file=sys.stderr)


def parse_plan_new_ids(path):
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    # Capture the Stage 4 table rows. The header "ID" is uppercase, so the
    # snake_case rows are exactly the 20 new look IDs.
    ids = re.findall(r"^\|\s*([a-z_][a-z0-9_]*)\s*\|", text, re.MULTILINE)
    return ids


def extract_look_blocks(text):
    """Return each top-level Look(...) initializer as a string.

    Balanced-paren scanner that skips strings.
    """
    blocks = []
    i = 0
    while True:
        start = text.find("Look(", i)
        if start == -1:
            break
        depth = 0
        in_str = None
        end = None
        j = start
        while j < len(text):
            c = text[j]
            if in_str:
                if c == "\\" and j + 1 < len(text):
                    j += 2
                    continue
                if c == in_str:
                    in_str = None
            else:
                if c == '"':
                    in_str = '"'
                elif c == '(':
                    depth += 1
                elif c == ')':
                    depth -= 1
                    if depth == 0:
                        end = j
                        break
            j += 1
        if end is None:
            break
        blocks.append(text[start:end + 1])
        i = end + 1
    return blocks


def parse_filter_looks(path):
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()

    looks = []
    for block in extract_look_blocks(text):
        idm = re.search(r'id:\s*"([^"]+)"', block)
        # categories: [.forYou, .makeup]  or  categories: Category.allCases
        catm = re.search(
            r'categories:\s*(?:\[([^\]]*)\]|([A-Za-z_][A-Za-z0-9_.]*))',
            block,
        )
        texm = re.search(r'makeupTex:\s*"([^"]+)"', block)
        looks.append({
            "id": idm.group(1) if idm else None,
            "categories": catm.group(1) if (catm and catm.group(1) is not None)
                           else (catm.group(2) if catm else ""),
            "makeupTex": texm.group(1) if texm else None,
        })
    return looks


def parse_makeup_studio(path):
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    # Match the array after the = sign, not the [(String?, String)] type.
    m = re.search(
        r'static let textures:.*?=\s*\[\s*(.*?)\s*\]',
        text,
        re.DOTALL,
    )
    if not m:
        return []
    block = m.group(1)
    return [
        (it.group(1), it.group(2))
        for it in re.finditer(
            r'\(\s*(?:nil|"([^"]*)")\s*,\s*"([^"]+)"\s*\)',
            block,
            re.DOTALL,
        )
    ]


def validate_png(path, errors):
    fname = os.path.basename(path)
    try:
        img = Image.open(path)
    except Exception as exc:  # noqa: BLE001
        error(errors, f"{fname}: cannot decode PNG: {exc}")
        return

    if img.size != (SZ, SZ):
        error(errors, f"{fname}: expected {SZ}x{SZ}, got {img.size}")
        return
    if img.mode != "RGBA":
        error(errors, f"{fname}: expected RGBA, got {img.mode}")
        return

    alpha = img.getchannel("A")
    hist = alpha.histogram()
    total = sum(hist)
    nonzero = total - hist[0]
    nonfull = total - hist[255]

    if nonzero == 0:
        error(errors, f"{fname}: alpha coverage is zero (fully transparent)")
    if nonfull == 0:
        error(errors, f"{fname}: alpha coverage is full (fully opaque)")

    # Mouth seam: inner lip polygon should stay meaningfully transparent.
    mask = Image.new("L", (SZ, SZ), 0)
    ImageDraw.Draw(mask).polygon(MOUTH_INNER, fill=255)
    seam = ImageStat.Stat(alpha, mask=mask)
    mean_a = seam.mean[0]
    min_a, max_a = seam.extrema[0]
    if mean_a > MOUTH_MEAN_MAX or max_a > MOUTH_MAX_MAX:
        error(errors, (
            f"{fname}: inner mouth seam too opaque "
            f"(mean={mean_a:.1f}, max={max_a}; limits mean<={MOUTH_MEAN_MAX}, max<={MOUTH_MAX_MAX})"
        ))


def main():
    parser = argparse.ArgumentParser(
        description="Validate makeup catalog and bundled assets",
    )
    parser.add_argument(
        "--assets-dir",
        default=ASSETS_DIR,
        help="Directory containing makeup_*.png plates",
    )
    parser.add_argument(
        "--filter-looks",
        default=FILTER_LOOKS_PATH,
        help="Path to FilterLooks.swift",
    )
    parser.add_argument(
        "--makeup-studio",
        default=MAKEUP_STUDIO_PATH,
        help="Path to MakeupStudio.swift",
    )
    parser.add_argument(
        "--plan",
        default=PLAN_PATH,
        help="Path to MAKEUP_REALISM_PLAN.md",
    )
    args = parser.parse_args()

    errors = []

    # ── Parse contracts ─────────────────────────────────────────────────────
    new_ids = parse_plan_new_ids(args.plan)
    if len(new_ids) != 20:
        error(errors, f"plan parsed {len(new_ids)} new IDs, expected 20: {new_ids}")

    looks = parse_filter_looks(args.filter_looks)
    if not looks:
        error(errors, f"could not parse {args.filter_looks}")

    studio_items = parse_makeup_studio(args.makeup_studio)
    studio_files = {item[0] for item in studio_items if item[0]}

    makeup_looks = [
        lk for lk in looks
        if lk["id"] and lk["id"] != "none" and ".makeup" in (lk["categories"] or "")
    ]
    makeup_ids = [lk["id"] for lk in makeup_looks]

    if len(makeup_ids) != 55:
        error(errors, f"Makeup rail has {len(makeup_ids)} presets, expected 55")
    if len(set(makeup_ids)) != len(makeup_ids):
        seen = set()
        dups = {x for x in makeup_ids if x in seen or seen.add(x)}
        error(errors, f"duplicate makeup look IDs: {sorted(dups)}")

    # ── 20 new IDs present with matching generated plate ─────────────────────
    missing_new = set(new_ids) - set(makeup_ids)
    if missing_new:
        error(errors, f"missing new look IDs: {sorted(missing_new)}")
    for lk in makeup_looks:
        if lk["id"] in new_ids:
            expected = f"makeup_{lk['id']}.png"
            if lk["makeupTex"] != expected:
                error(errors, (
                    f"new look '{lk['id']}' should use {expected}, "
                    f"got {lk['makeupTex']!r}"
                ))

    # Natural and Belle must be procedural (no makeupTex); all other makeup
    # looks use a plate.
    procedural = {lk["id"] for lk in makeup_looks if not lk["makeupTex"]}
    if procedural != {"natural", "belle"}:
        error(errors, (
            f"expected procedural looks to be exactly natural and belle, "
            f"got {sorted(procedural)}"
        ))

    # All look IDs, not only makeup, must be unique.
    all_ids = [lk["id"] for lk in looks if lk["id"] and lk["id"] != "none"]
    if len(set(all_ids)) != len(all_ids):
        seen = set()
        dups = {x for x in all_ids if x in seen or seen.add(x)}
        error(errors, f"duplicate look IDs in FilterLooks.all: {sorted(dups)}")

    # ── face_fx textures and wiring ─────────────────────────────────────────
    face_fx_texs = {lk["makeupTex"] for lk in makeup_looks if lk["makeupTex"]}
    expected_tex_count = 55 - 2  # natural and belle are procedural; the rest use a plate
    if len(face_fx_texs) != expected_tex_count:
        error(errors, (
            f"expected {expected_tex_count} face_fx makeup textures, "
            f"found {len(face_fx_texs)}"
        ))

    # ── Files on disk match references and Studio picker ────────────────────
    if not os.path.isdir(args.assets_dir):
        error(errors, f"assets directory missing: {args.assets_dir}")
        # Can't proceed with PNG checks.
        print("ABORT: assets directory missing", file=sys.stderr)
        sys.exit(1)

    png_files = {
        f for f in os.listdir(args.assets_dir)
        if f.startswith("makeup_") and f.endswith(".png")
    }

    missing_files = face_fx_texs - png_files
    if missing_files:
        error(errors, f"face_fx textures missing on disk: {sorted(missing_files)}")

    extra_files = png_files - face_fx_texs
    if extra_files:
        error(errors, f"unexpected makeup_*.png on disk not in catalog: {sorted(extra_files)}")

    unwired = png_files - studio_files
    if unwired:
        error(errors, f"plates not exposed in MakeupStudio picker: {sorted(unwired)}")

    # ── Decode and validate every bundled plate ─────────────────────────────
    for fname in sorted(png_files):
        validate_png(os.path.join(args.assets_dir, fname), errors)

    # ── Summary ─────────────────────────────────────────────────────────────
    if errors:
        print(f"\nmakeup catalog/asset validation FAILED ({len(errors)} issue(s))", file=sys.stderr)
        sys.exit(1)

    print(f"OK: {len(makeup_ids)} Makeup presets, {len(new_ids)} new IDs, "
          f"{len(png_files)} plates on disk, all wired and decoded.")
    sys.exit(0)


if __name__ == "__main__":
    main()
