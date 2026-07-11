# Makeup realism expansion plan

Status: approved direction and execution plan, 2026-07-10.

## Goal

Make the existing face-tracked makeup collection read as cosmetics integrated with living skin instead of flat UV decals, preserve identity with makeup-first shaping, and add 20 production-ready looks. Preview, recording, and export must continue to use the same `face_fx` render path.

## Direction locked with the user

- North star: balanced collection—polished glam, e-girl/doll, romantic, smoky, jewel-tone, gothic, and restrained fantasy.
- Shape: makeup-first. Morphs remain subtle and must preserve identity.
- Skin: mixed by look. Natural/glam presets preserve texture; doll/e-girl presets may use controlled porcelain smoothing.
- Lips: balanced gloss, satin, blurred-gradient, and velvet-matte finishes.
- Collection: broad rather than 20 near-duplicates.

## Reference signatures

The supplied references consistently show:

- Skin: satin or satin-matte base. Even tone without erasing every pore; porcelain smoothing is a deliberate stylized exception.
- Sculpting: soft under-cheek contour, nose-side shading, and small highlights on cheekbones, nose bridge/tip, cupid’s bow, and chin. No hard contour stripes.
- Eyes: a light inner/lid base, deeper crease and outer V, sharp but anatomically anchored wings, dense upper lashes with varied clusters, restrained lower lashes.
- E-girl: diffused cheek-to-nose blush, irregular freckles, doll lashes, and pink gloss.
- Glam: warm terracotta/brown depth, lifted cheek color, defined brows with hair texture, nude lip liner, and dimensional center gloss.
- Editorial: jewel-tone lids work when cheeks stay restrained and lips remain dimensional.
- Realism cues: translucent pigment, nonuniform edges, asymmetric detail, retained skin variation, expression-safe eye/lip masks, and highlights that follow existing luminance rather than opaque white stickers.

## Problems in the current implementation

1. `tools/gen_makeup_elements.py` mostly paints one blurred color per feature. Eyes lack lid/crease/outer-V depth; cheek color uses radial discs; lashes are evenly spaced; brows are blurred bars; gloss is a single white blob.
2. Existing generated plates are nearly mirrored and uniformly opaque. They read as decals when the face turns or lighting changes.
3. The mesh compositor performs global luma adaptation but treats every texel alike. Dark pigment, translucent blush, and bright gloss need different responses.
4. Several existing iOS presets use aggressive smoothing and morph values, especially Doll Pink, Glam Contour, Cold Beauty, Angel, and Cyber Chrome.
5. The Studio plate picker exposes only the current 13 textures.
6. There is no deterministic gate proving every preset references a bundled, decodable texture.

## Implementation

### Stage 1 — richer deterministic texture painter

Update `../pop-maker-studio/tools/gen_makeup_elements.py` in place; keep one data table and one generation command.

- Replace single-stroke eyeshadow with layered lid wash, crease, outer-V depth, inner-corner light, and optional center shimmer.
- Add directional blush families: lifted, apple, draped/nose-band, sun-kissed, and sculpted. Use translucent stacked passes instead of one opaque ellipse.
- Separate contour from blush. Add soft cheekbone, temple/jaw, and nose-side shading with warm/cool variants.
- Rework lips into liner/base/center layers. Support satin, wet gloss, velvet matte, blurred gradient, bitten, and soft overline while preserving the mouth seam.
- Rework lashes as tapered, irregular clusters with style controls (wispy, doll, cat, stage) and restrained lower-lash options.
- Rework brows as seeded hair strokes with soft density underneath.
- Make freckles deterministic but irregular in size, opacity, hue, and placement.
- Add satin/pearl/glass highlight styles with low-opacity lobes instead of flat white spots.
- Seed small left/right variation per look. Generation remains byte-deterministic.

### Stage 2 — lighting-aware mesh composite

Update the shared face makeup fragment path in `../pop-maker-studio/src/metal_render.mm` and its desktop twin only where parity requires it.

- Preserve the source face’s luminance and high-frequency detail under translucent pigment.
- Treat texture luminance as material intent: dark texels deepen/multiply, midtone chroma tints, and bright low-alpha texels add restrained highlight.
- Gate makeup with existing confidence/blink behavior; keep the inner-mouth seam clear.
- Avoid additional render passes or per-frame allocations.
- Extend the focused Metal face test with representative dark pigment and gloss assertions.

### Stage 3 — retune the 15 existing looks

- Regenerate all data-driven plates: Doll Pink, E-Girl, Glam Contour, Coquette, Goth, Peach, Cold Beauty, Sunset, Angel, Baddie, Cyber Chrome, and Freckle Doll.
- Retune iOS `face_fx` values: lower default smoothing/morphs for identity preservation; use procedural blush/lip/lash only when they add depth rather than doubling the plate.
- Retune engine recipes used by Natural, Douyin Glam, and Belle so their defaults follow the same realism envelope.
- Keep recognizable signatures: Doll Pink remains porcelain and rosy; E-Girl keeps nose blush/freckles; Glam keeps sculpting; Goth keeps deep pigment; Cyber Chrome remains intentionally editorial.

### Stage 4 — add 20 looks

All IDs are stable snake case; each gets a generated `makeup_<id>.png`, an iOS rail entry, and a Studio plate entry.

| ID | Label | Signature | Skin / morph envelope | Lip finish |
|---|---|---|---|---|
| clean_girl | Clean Girl | sheer lifted blush, groomed brow, tightline | pore-preserving; near-zero morph | satin balm |
| soft_glam_nude | Soft Glam Nude | taupe crease, wispy lash, soft contour | satin; subtle sculpt | nude gloss |
| bronze_sculpt | Bronze Sculpt | bronze lid and lifted warm contour | satin-warm; subtle cheek/jaw | satin nude |
| latte | Latte | monochrome coffee eye/cheek/lip | pore-preserving; minimal morph | velvet nude |
| rosewood | Rosewood | rose-brown lid and softly lined lip | satin; subtle eye/lip | satin rose |
| champagne_glow | Champagne Glow | neutral crease, pearl highlight | luminous satin; minimal morph | clear gloss |
| peach_sorbet | Peach Sorbet | peach lid, cheek, and blurred lip | soft satin; subtle eye | blurred gradient |
| berry_bitten | Berry Bitten | restrained eye, berry center lip | natural skin; no jaw sculpt | bitten stain |
| cherry_gloss | Cherry Gloss | clean wing and dimensional red gloss | satin; subtle lip plump | wet gloss |
| terracotta_smoke | Terracotta Smoke | deep warm crease and outer V | pore-preserving; subtle eye | satin clay |
| emerald_smoke | Emerald Smoke | jewel-green layered eye, quiet cheek | satin; minimal morph | neutral gloss |
| sapphire_night | Sapphire Night | blue-teal lid depth and sharp wing | satin; subtle eye | glossy nude |
| plum_velvet | Plum Velvet | plum smoke and cool sculpt | soft matte; minimal morph | velvet plum |
| mocha_siren | Mocha Siren | elongated brown wing, cat lashes | satin; subtle eye/cheek | lined gloss |
| romantic_rose | Romantic Rose | rose wash, pearl inner corner | soft satin; subtle eye | rose gloss |
| ballet_pink | Ballet Pink | airy pink lid, doll lash, soft flush | controlled porcelain; subtle eye | satin pink |
| sunkissed_freckles | Sunkissed Freckles | warm nose band and sparse freckles | pore-preserving warm skin | balm |
| grunge_smoke | Grunge Smoke | imperfect charcoal-brown smoke | texture-preserving; no morph | blurred matte |
| midnight_goth | Midnight Goth | deeper dimensional black-plum eye | soft matte; subtle eye | black-cherry satin |
| opal_fantasy | Opal Fantasy | restrained lavender/blue shift and pearl light | luminous; subtle eye | iridescent gloss |
| anime_doll | Anime Doll | turquoise iris, doll lashes, graphic liner, glossy pink lip | satin; subtle eye | wet gloss |
| kawaii_glitter | Kawaii Glitter | blue iris, glitter pink lid, graphic liner, doll lash | satin; subtle eye | gloss |
| pastel_fairy | Pastel Fairy | violet iris, lavender lid, wispy lash, dark arched brow | satin; subtle eye | gloss |
| platinum_cat | Platinum Cat | gray-blue iris, thin blonde brow, siren liner, cat lash | satin; subtle sculpt | satin |
| teal_smoke_doll | Teal Smoke | teal-copper lid, stage lash, wing liner | satin-warm; subtle eye | gloss |
| rose_gold_doll | Rose Gold | amber iris, champagne lid, doll lash, wing liner | satin; subtle eye | gloss |
| chocolate_crease | Chocolate Crease | brown cut-crease, stage lash, dark brow, matte nude lip | satin; subtle sculpt | matte |
| soft_doe_red | Doe Red | peach crease, wispy lash, tightline, red matte lip | pore-preserving; minimal morph | matte |
| bronze_cat_eye | Bronze Cat | bronze lid, cat lash, siren liner, glossy pink-nude lip | satin; subtle sculpt | gloss |
| kawaii_blush | Kawaii Blush | heavy band blush, doll lash, soft liner, glossy rose lip | satin; subtle eye | gloss |
| peach_egirl_freckle | Peach E-Girl | hazel iris, band blush, freckles, wing liner, wispy lash | pore-preserving; minimal morph | balm |
| soft_amber_doll | Amber Doll | amber iris, warm lid, doll lash, soft liner, glossy lip | satin; subtle eye | gloss |
| gamer_belle | Gamer Belle | blue iris, band blush, freckles, doll lash, wing liner | satin; subtle eye | gloss |
| glitter_cat_pink | Glitter Cat | blue iris, glitter pink lid, graphic liner, cat lash | satin; subtle eye | gloss |
| pastel_kitten | Pastel Kitten | violet iris, pastel pink lid, wispy lash, wing liner | satin; subtle eye | satin |
| crescent_boho | Boho Crescent | light blue iris, neutral lid, stage lash, soft liner | satin; minimal morph | satin |
| soft_amber_glow | Amber Glow | amber iris, warm lid, wispy lash, soft liner | satin; subtle eye | gloss |
| dramatic_nude_glam | Nude Glam | cut-crease, stage lash, wing liner, glossy nude lip | satin; subtle sculpt | gloss |
| warm_bronze_teal | Bronze Teal | bronze lid + teal lower, stage lash, siren liner | satin-warm; subtle eye | gloss |
| grunge_fairy | Grunge Fairy | hazel-green iris, dark smoke, wispy lash, graphic liner | texture-preserving; no morph | blurred matte |

### Stage 5 — iOS catalog and Studio

- Add the 20 looks to `App/Sources/FilterLooks.swift` in a readable rail order.
- Add all 20 plate names to `MakeupStudioSheet.textures`.
- Copy generated PNGs into `Engine/EngineAssets/models/face/`; folder-resource bundling then includes them automatically.
- Keep all look construction data-driven. No per-look shader branch or enum.

## Verification

1. Run the texture generator twice and compare hashes to prove deterministic output.
2. Assert every generated PNG is 1024×1024 RGBA, has nonzero but non-full alpha coverage, and has a nonempty mouth seam.
3. Add/run a focused catalog contract that checks: 35 total makeup presets (15 existing + 20 new), unique IDs, every `face_fx` texture exists, and every Studio texture exists.
4. Run `face-smoke` to protect tracking inputs.
5. Run the Metal `face_fx` focused case on a macOS Metal host; verify dark pigment preserves detail and gloss does not clip into a white decal.
6. Generate the Xcode project and run the simulator build for Swift/catalog/resource integration.
7. On device, spot-check Natural, E-Girl, Glam Contour, Clean Girl, Cherry Gloss, Emerald Smoke, Midnight Goth, and Opal Fantasy at 0%, 50%, and 100% intensity; check neutral face, blink, smile, yaw, mixed lighting, and two faces.

## Completion criteria

- Existing looks are visibly less flat and less identity-altering while retaining their names and signatures.
- Exactly 20 additional looks appear in the Makeup rail and Studio plate picker.
- Every new look uses the existing tracked mesh and records WYSIWYG.
- No missing texture silently falls back to procedural-only rendering.
- Generator determinism, focused engine checks, and iOS build all pass; hardware-only visual QA is explicitly reported if unavailable.
