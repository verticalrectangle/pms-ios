#!/usr/bin/env python3
"""20 PopMaker Studio icon variants — raw bokeh orbs on light ground.

5-orb cluster composition (tighter, reads at icon scale) on Theme.ground light
#F2F4F7. No glass disc, no glyph — just the AtmosphereView glossy 3D bokeh
spheres filling the whole rounded-square tile. Mix of curated triads and
monochrome shade families from the video editor's 12 UI hues.

Emits TSV: tag  comp  ground_hex  orb_colors
(exactly 20 rows, all distinct)."""
import colorsys

HUES = {
    "lavender": 0xB5A8FF, "ice": 0x82D1FF, "mint": 0x75E6B3, "ember": 0xFFA876,
    "rose": 0xFF8CB8, "gold": 0xFFCC6B, "violet": 0xC79EFF,
    "blu": 0x6B99FF, "emb": 0xFFAE80, "pink": 0xFF5CA8, "cblu": 0x4A6BFF, "cpur": 0xA85CFF,
}
GROUND = "F2F4F7"
H = list(HUES)

def to_hsv(c):
    r,g,b=((c>>16)&0xFF)/255,((c>>8)&0xFF)/255,(c&0xFF)/255
    return colorsys.rgb_to_hsv(r,g,b)
def from_hsv(h,s,v):
    r,g,b=colorsys.hsv_to_rgb(h,s,v)
    return (round(r*255)<<16)|(round(g*255)<<8)|round(b*255)
def deepen(c):
    h,s,v=to_hsv(c); return from_hsv(h,min(1,s+0.12),v*0.82)
def lighten(c):
    h,s,v=to_hsv(c); return from_hsv(h,s*0.6,min(1,v*1.18))

rows = []
def add(tag, orb_colors):
    rows.append((tag, "cluster", GROUND, orb_colors))

# ── 10 curated triads: 3 hues spread across the palette ──
triads = [
    ("lav-blu-emb",   ["lavender","blu","emb"]),
    ("pink-cblu-cpur",["pink","cblu","cpur"]),
    ("ice-mint-gold", ["ice","mint","gold"]),
    ("rose-violet-blu",["rose","violet","blu"]),
    ("ember-gold-pink",["ember","gold","pink"]),
    ("lav-rose-mint",  ["lavender","rose","mint"]),
    ("cpur-ice-ember", ["cpur","ice","ember"]),
    ("cblu-violet-mint",["cblu","violet","mint"]),
    ("blu-cpur-gold",  ["blu","cpur","gold"]),
    ("pink-lav-ice",   ["pink","lavender","ice"]),
]
for name, triad_hues in triads:
    colors = ",".join(f"{HUES[h]:06X}" for h in triad_hues)
    add(f"pms-triad-{name}", colors)

# ── 10 monochrome shade families: base/deep/light of one hue ──
mono_hues = H[:10]  # first 10 hues
for n in mono_hues:
    b, d, l = HUES[n], deepen(HUES[n]), lighten(HUES[n])
    add(f"pms-mono-{n}", f"{b:06X},{d:06X},{l:06X}")

assert len(rows) == 20, f"expected 20, got {len(rows)}"
assert len(set(rows)) == 20, "duplicate variants"

for r in rows:
    print("\t".join(r))
