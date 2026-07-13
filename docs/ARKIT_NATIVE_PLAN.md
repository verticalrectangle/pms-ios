# ARKit-Native Makeup Rendering — Plan & Status

2026-07-12. Supersedes the 2D landmark-bridge architecture on the ARKit tier
(tier 1, TrueDepth front camera). Tiers 2/3 (CoreML sync rear / MediaPipe
async) keep the existing MP screen-space path unchanged.

## Why

Eight consecutive on-device failures came from one architectural decision:
projecting ARKit's 1220 3D vertices to 2D in Swift, evaluating 478 MediaPipe
landmarks through a static canonical-head correspondence table, and rendering
makeup in screen space. Every fix hand-reimplemented information ARKit
already provides:

| Round | Failure | Root cause | Native answer |
|---|---|---|---|
| 1–5 | makeup misplacement, under-eye band on cheek | canonical correspondence ≠ live face | no correspondence exists |
| 5, 8 | blink under-tracking (77%), lash line floating above lashes | static barycentric blends can't express "on the lid edge" | lash line = mesh hole rim, pigment rides skin |
| 6 | lashes descend chop-by-chop | mixed vertex attachments, different blink gains | texture on the surface moves with the surface |
| this | lashes wobble one by one | raw per-vertex tracking noise passed through | pigment is sub-pixel-stable on the surface |
| 7 | makeup floats off face during motion | landmarks projected with a cached camera from a different frame; isTracked ignored | verts + matrices + pixels ship in one ARFrame |
| 8 | iris painted on lids, ignored gaze; blink fade dead | mesh is eyeball-blind; blendshape array misindexed | leftEye/rightEyeTransform are the actual eyeball poses |

The lesson is structural: **render ARKit's own mesh, in 3D, with ARKit's own
camera, textured in ARKit's own UV space.** Alignment becomes true by
construction; expressions and blinks carry the makeup because they carry the
skin.

## Architecture

- Swift ships, per ARFrame: 1220 model-space 3D vertices, anchor transform,
  camera view matrix, portrait projection matrix, left/right eye transforms,
  blendshapes, isTracked. Same callback as the video frame — desync is
  impossible.
- Engine (`metal_render.mm` face_fx block) branches: 3D slot fresh → native
  path; else tier 2/3 as today.
- Native path passes:
  1. **Makeup mesh**: ARKit topology (`k_arkit_tris`) + real ARKit UVs
     (generated `k_arkit_uv`), MVP = proj·view·model, back-face culled,
     sampling the look's ARKit-UV atlas with the same luminance adaptation
     as the MP mesh pass. Writes stencil.
  2. **Eye layer**: iris discs placed from the eye transforms (pupil =
     eyeball center + gaze·r), stencil-tested so they render only through
     the mesh's eye holes — gaze-true, lid-clipped, vanish on blink
     geometrically.
  3. **Beauty pass** (existing fullscreen skin shader): keeps smoothing /
     tone / warp; its landmark uniforms come from a ~20-entry hand-verified
     ARKit vertex index list projected CPU-side. Procedural eye/lip/blush
     elements are OFF on this tier — the atlas carries them.
  4. **Debug overlay** (`face_overlay` IPC): checker texture + projected key
     verts instead of the 478-dot cloud.
- Makeup content: per-look **ARKit-UV atlases** baked offline by
  `tools/gen_arkit_makeup.py`:
  - plate PNGs (MakeupStudio, MP-UV space) resampled through a precomputed
    MP-UV→ARKit-UV warp map (canonical correspondence used offline, where
    its error is tolerable diffuse-pigment placement, not per-frame motion);
  - builtin looks (Goth, Barbie, CatEye, …) painted programmatically in
    ARKit UV from ring topology: lip bounded by the real lip rings (mouth
    interior is a hole — teeth unpaintable), shadow band from the eye-hole
    rim (the rim IS the lash line), liner/lash fringe along the rim, blush /
    freckles / contour zones.
- Staleness (>0.15 s) and isTracked clearing carry over to the 3D slot.

## Phases

- [ ] **Phase 0 — Real-face fixtures.** Debug recorder in the app dumps
  per-frame geometry (+ every-Nth JPEG) to Documents (file sharing on);
  synthetic fixture generator (canonical mesh + scripted blink/gaze/pose)
  keeps CI honest until real captures land. Replay drives all later gates.
- [ ] **Phase 1 — Native mesh renderer.** `pms_submit_arkit_face_3d` ABI;
  engine draws the mesh with a UV-checker over the frame. Accept: checker
  glued to the face at every pose in replay + on device.
- [ ] **Phase 2 — ARKit-UV atlases.** Warp-map baker + plate conversion +
  builtin-look layers; `BeautyLook.arkit_tex` wiring; intensity scales atlas
  opacity.
- [ ] **Phase 3 — Eye layer.** Stencil-clipped iris discs from eye
  transforms; iris tint/anime params move here.
- [ ] **Phase 4 — Retire the 2D bridge on this tier.** Beauty params from
  projected ARKit key verts; Swift stops calling the 2D submit; bridge stays
  for tiers 2/3 only.
- [ ] **Phase 5 — post-QA polish (needs on-device judgment of v1).** 3D lash
  cards standing off the lid; glasses occlusion via the existing person
  matte; per-look art passes.

## Gates

- `arkit-native-replay` (Mac): renders fixture frames through the real
  engine; asserts makeup stays inside the projected face, shadow rows track
  the lid on blink frames, iris follows scripted gaze; writes PNGs for
  eyes-on review.
- Existing gates stay green untouched: `engine-smoke`, `arkit-map-smoke`
  (tier-2/3 bridge), `metal-render-test` (MP path), iOS device build.

## Risks

- ARKit UV layout quality at the eye rim — checked visually in Phase 1.
- Metal NDC/orientation conventions for the portrait projection — settled
  once with the checker + synthetic fixture.
- Atlas art quality needs iteration with real eyes; the pipeline makes that
  a texture edit, not an engine change.
