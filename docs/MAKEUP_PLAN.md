# MAKEUP_PLAN — face-tracked makeup looks + the look creation system

Status: rev 1 (2026-07-10). Follows RECORD_PLAN (committed, gates green).
Decisions locked with the user: **MediaPipe/ONNX** face stack (desktop
parity), **Full Makeup Studio** (presets + per-feature morph sliders + layer
mixing + saved custom looks), chroma-on-camera fixed with **matte-keying AND
tap-to-pick key color**, face models **bundled in the app**.

## Goal

Real makeup filters in RecordView — landmark-tracked, expression-reactive,
morphing toward "real beautiful beauty" (doll eyes, slimmed jaw, plumped
lips, blush/freckles/liner/lashes/lip tint painted onto the tracked face) —
in the genre of the four reference images (Doll Pink, E-Girl freckles, full
Glam contour, Douyin ivory). Not one-off filters: a **creation system** that
mass-produces variants from data (element textures × colors × morph recipes),
plus an in-app Studio so users compose and save their own. Target: visibly
better than CapCut's beauty mode — because ours is expression-reactive
(blendshapes), engine-rendered (preview == export), and non-destructive on
the timeline.

## What exists (verified 2026-07-10)

Desktop engine already has the hard parts:
- `src/face_track.{h,cpp}` — YuNet detector (fixed 640×640 BGR blob) +
  MediaPipe Face Landmarker v2 (478-pt mesh incl. iris) + 52 ARKit-style
  blendshapes (146-landmark subset input), all via ONNX Runtime on a worker
  thread, EMA-smoothed. `face_track_available()` checks
  `<models_dir>/face/{yunet,face_landmarks_v2,face_blendshapes}.onnx`.
- `src/paths.cpp app_models_dir()` — **asset-root-wins**: on iOS, bundled
  `models/` under the pms_create asset root is found first. Bundling = drop
  files in the app bundle.
- `src/face_filters.{h,cpp}` — `FaceWarpBump` fields (≤20 local radial
  scale/shift bumps), `face_filter_bumps()` recipes (~35 looks: Doll,
  Coquette, EGirl, Belle, Barbie, …), `MakeupLook`
  (smooth/brighten/warmth/eye_pop/blush/lip + colors + UV makeup texture),
  UV-space makeup PNGs painted by `tools/paint_makeup_douyin.py` against
  `tools/canonical_face_model.obj` (MediaPipe topology,
  `src/generated/face_uv_mesh.h`).
- ONNX Runtime is **already linked in the iOS app** (project.yml).
- Both compiled into the engine library already (`face_track.cpp`,
  `face_filters.cpp` in the engine sources) — the GL-only apply paths are
  what's missing on Metal.

Missing / broken (this plan):
1. **Camera path bugs** (user-reported "chroma filters don't show"): (a) the
   engine renders the scene compositor whenever any layer frame exists, and
   LayerFeeder keeps submitting while RecordView is up — in any project with
   clips the camera is invisible and set_live_fx does nothing; (b) chroma FX
   default to a pure-green key, which is identity on a selfie with no green.
2. No Metal port of face warp / makeup composite / skin passes.
3. No face models on device; no camera→tracker feed on iOS.
4. No data-driven look system — desktop looks are C++ recipes; textures are
   one-off scripts. No Studio UI anywhere.

## Stage 0 — fix the camera path (blocks everything else)

- **Layer shadowing**: new engine command `clear_layer_frames` (erases the
  layer store + releases mappings). RecordView on appear: suspend
  `model.layers` (`suspended = true`), stop the base-frame sink, send
  `clear_layer_frames`; on dismiss: restore feeder, `syncLiveFX()`, nudge a
  refresh so the timeline re-feeds. The engine then falls back to the
  single-content (camera) path, where the live stack applies.
- **Live-stack ownership**: while RecordView is up, EditorModel must not
  clobber the record stack (`syncLiveFX` fires on refresh). Add
  `model.liveFXSuspended` flag checked by `syncLiveFX()`.
- **Matte-keyed chroma**: chroma passes gain `matte_key` (param, 0/1). When
  set and a person matte is bound, the foreground term comes from the matte
  instead of color distance: subject stays crisp, the background melts /
  echo-stacks / frame-delays. Manifest extras + desktop inspector get the
  param; run_fx_stack binds the matte at texture(2) for chroma entries;
  Record looks set `matte_key: 1` and enable VisionMatte.
- **Tap-to-pick key**: CameraCapture keeps the latest BGRA frame;
  RecordView tap (when a chroma look is active) samples the pixel under the
  finger (preview UVs → buffer coords incl. aspect-fit + mirror) and pushes
  `chroma_*_r/g/b` into the live stack. Double-tap resets to matte mode.

Gate: metal-render-test `l.chroma_feedback` extended with a matte-keyed
variant (synthetic matte, assert background-only trails).

## Stage 1 — face models + tracking on iOS

- **Provisioning**: `tools/fetch_face_models.py` downloads + verifies
  (sha256, tensor I/O names/shapes probed with onnxruntime) into
  `models/face/`. YuNet from OpenCV Zoo (MIT); landmarker v2 + blendshape
  nets as ONNX conversions of the Apache-2.0 MediaPipe models (exact source
  pinned in the script; the face_track.cpp I/O contract — YuNet
  `cls_/obj_/bbox_/kps_{8,16,32}`, 146-pt blendshape subset — is the
  acceptance test). **Risk**: finding conversions that match the expected
  tensor names; fallback is converting locally (tflite2onnx) and pinning
  artifacts.
- **iOS bundling**: pms-ios `Engine/models/face/*.onnx` (git-lfs or plain
  blobs ~15 MB) → project.yml resources → lands under the app asset root;
  `app_models_dir()` finds them (asset-root-wins already implemented).
- **Feed**: engine-side — `pms_submit_camera_frame` also side-feeds the face
  worker (BGRA CVPixelBuffer → ~256-px RGB downscale, engine-side, only when
  face tracking has been enabled via a `face_track_enable` command so plain
  recording pays nothing). Rotation matches the upright camera contract.
- Gate: engine-level probe command `face_debug` returns
  {models_present, worker_alive, last_score, pts_valid} — asserted in
  metal-render-test (models present on the Mac) with a synthetic face image
  (the embedded picker base photo).

## Stage 2 — Metal face passes

Hand-written passes in metal_render.mm (body/chroma pattern), driven by a new
live-stack entry `fx_type: "face_fx"`:

- **face_warp** — one fullscreen pass applying ≤20 `FaceWarpBump`s (uniform
  array; same math as the desktop GLSL: local radial scale + shift with
  smooth falloff). Bumps come from `face_filter_bumps()`-style recipes
  computed CPU-side from the latest FaceObs + the entry's morph params
  (eyes/jaw/nose/lips/slim × amount), blendshape-modulated (blink squashes
  eye bumps — desktop parity).
- **makeup_mesh** — renders the tracked 478-pt mesh (canonical triangulation
  from `face_uv_mesh.h`) as a vertex pass: position = FaceObs pts (frame
  UV), texcoord = canonical UV; fragment samples the composited makeup
  texture with luma adaptation (`makeup_adapt`) and premultiplied-over
  blends onto the frame. Occlusion realism v1: alpha rides the landmark
  score; no depth test.
- **skin pass** — reuse the existing registry beauty shaders
  (porcelain_skin et al.) chained before the mesh pass; face_fx's
  smooth/brighten map onto them so nothing new is written.
- **Makeup texture compositing** — element layers composited to one RGBA
  texture engine-side at look-select (CPU compose of PNG layers × tint
  color × alpha; cached per look hash).
- **Export parity**: face_fx entries in a take's brick re-run the tracker on
  decoded frames during export (`face_track_build_cache` exists engine-side
  for the take path — reuse it).
- Gate: metal-render-test `m.face_fx` — inject a synthetic FaceObs (fixed
  landmark set), assert warp displaces a known pixel and the mesh pass
  paints the blush region; runs without ONNX so CI never needs models.

## Stage 3 — the creation system (many many variants)

Data over code:

- **`effects/face_elements/`** — parameterized element painters in
  `tools/gen_makeup_elements.py` (extends paint_makeup_douyin.py):
  blush {round, band, douyin_high, sun}, lips {full, gradient_kiss, matte,
  gloss, overline}, liner {wing, siren, puppy, graphic}, lashes {doll, cat,
  wispy, stage}, freckles {scatter, dense, hearts}, contour {soft, snatched},
  highlight {glass, pearl}, brows {straight, arched, fluffy}, extras
  {aegyo_sal, nose_blush, gems}. Each renders to a 1024² canonical-UV RGBA
  PNG, **white-luma masks tinted at runtime** so one texture serves every
  color.
- **`effects/face_looks.json`** — the look registry: id, label, category,
  morphs {eyes, jaw, nose, lips, slim}, skin {smooth, brighten, warmth},
  layers [{element, variant, color, alpha}]. `tools/codegen_effects.py`
  grows a face-looks section → generated C++ table (desktop chips + engine
  defaults) + manifest entries (category **Makeup+**) for iOS.
- **~24 preset looks** including the four references: Doll Pink (huge doll
  eyes, porcelain, pink blush band, glossy lip), E-Girl (nose blush, dense
  freckles, wing liner, plump gloss), Glam Contour (snatched contour, fluffy
  brow, matte nude overline lip, stage lashes), Douyin Ivory (ivory skin,
  aegyo-sal, gradient red kiss lip, straight brow) — plus Coquette, Latte,
  Cold Beauty, Cyber Doll, Baddie, Angel, Sunset, …
- Element PNGs are checked in (generated, deterministic, ~50-150 KB each).

## Stage 4 — Makeup Studio (iOS)

- RecordView rail gains a **Makeup** category listing the preset face looks
  (they compose with color/chroma looks: face_fx entries prepend the stack).
- **Studio sheet** (wand button when a makeup look is active): morph sliders
  (Eyes, Jaw, Nose, Lips, Slim), skin sliders, and a layer list — each layer
  = element picker + variant + color swatch row + intensity; add/remove
  layers; live on the camera as you drag.
- **Save look**: named custom looks persisted as the same JSON shape
  (Documents/makeup_looks.json), loaded into the rail next to presets, and
  serialized into the take's brick params so projects round-trip.
- Landed takes carry face_fx in the coupled brick like every other look.

## Stage 5 — gates

Linux smoke + codegen determinism; Mac metal-render-test (chroma-matte,
face_fx synthetic cases) + xcframework + sim/device builds; regen catalog +
LEVERS; docs/memory; commit + push. On-device QA checklist for the user
(tracker latency, warp stability, Studio gestures) — the one gate I can't
run myself.

## Order of execution

Stage 0 ships alone first (it fixes the user-visible chroma bug even before
any face work). Then 1 → 2 → 3 → 4 with per-stage gates.

## Status log

- 2026-07-10: plan written; camera-path bugs diagnosed (layer shadowing +
  green-key identity); face stack + tooling recon complete.
- 2026-07-10 (same session): **Stages 0–4 executed, all gates green.**
  - Stage 0: `clear_layer_frames` command + RecordView frame-path ownership
    (feeder suspended, live-FX pushes guarded by `liveFXSuspended`); chroma
    passes gained `matte_key` (person matte as key — background trails behind
    the subject, no green screen; masked ring snapshots for chroma_frame);
    tap-to-pick key colour (samples the live camera buffer), double-tap back
    to matte mode. Fixed along the way: the legacy blit applied the matte
    cutout whenever a matte merely EXISTED — now gated on the stack's
    Remove-Background flag. Gate: `n.chroma_matte_key` (exact record path:
    set_live_fx + camera frames + half matte → subject crisp / bg ghosts).
  - Stage 1: `tools/fetch_face_models.py` downloads + converts + verifies
    YuNet (OpenCV Zoo) and the MediaPipe landmarker/blendshape tflites →
    ONNX (tf2onnx, exact tensor contract asserted); models live in
    `models/face/` (desktop) and `Engine/EngineAssets/models/face/` (bundled
    in the .app, asset-root-wins). Camera side-feed
    (`metal_render_face_feed`, gated by the `face_track_enable` command,
    `face_debug` for status). Gate: new `face-smoke` target — real
    detect→landmarks→blendshapes on assets/test_face.png → PASS (score 1.0).
  - Stage 2: `face_filter_build_plan_look()` extracted (platform-neutral
    param assembly, BeautyLook now public); Metal ports in metal_render.mm —
    `face_beauty_f` (full port: skin mask/smooth/brighten, blush, e-girl
    nose blush + freckles, lip polygon tint, lash/liner/wing, chin retouch,
    cyber layer), UV-mesh makeup pass (898-tri canonical topology,
    fold-culling, lighting adaptation, blink fade), `face_warp_f` (12
    bumps). `face_fx` live-stack entries carry a full BeautyLook as params +
    `face_makeup_tex` — presets AND custom Studio looks use one path. Gate:
    `o.face_fx` in metal-render-test — real models + tracker lock on the
    test portrait + Barbie look changes 15.8% of the frame. PASS.
  - Stage 3: `tools/gen_makeup_elements.py` — parameterized element painters
    (blush styles, shadow, aegyo-sal, freckles, lip styles incl. overline +
    gloss + bitten, liner styles incl. siren/graphic, lash hairs, highlight,
    brow, contour) composited per a LOOKS spec table → 12 look textures
    (doll_pink, egirl, glam_contour, coquette, goth, peach, cold_beauty,
    sunset, angel, baddie, cyber_chrome, hearts_freckles) + the existing
    douyin plate. Adding a variant = one spec entry + rerun.
  - Stage 4: Makeup rail category (15 face looks incl. the 4 reference
    images' genres); `MakeupStudio.swift` — full Studio sheet (skin/shape/
    makeup/cyber sliders, blush+lip color pickers, makeup-plate picker,
    live-on-camera edits, save → named custom looks persisted to
    Documents/makeup_looks.json and shown in the rail).
    **FilteredTakeRecorder**: takes are now WYSIWYG — every camera frame is
    re-rendered through the engine live-FX stack into the encoder, so
    makeup, matte chroma trails, and every look are IN the recorded pixels
    (no brick double-apply; the take lands clean).
  - Stage 5 gates: Linux full build + engine-smoke + face-smoke PASS;
    Mac metal-render-test PASS (all cases incl. k/l/n/o); xcframework
    rebuilt; sim (ENGINE_MOCK) + device builds SUCCEEDED with all 16 face
    assets verified inside the .app bundle.
  - Known gaps (next session candidates): face looks on TIMELINE playback of
    non-record footage (needs the face-cache port — takes are baked so this
    only matters for imported clips); desktop record-path parity for
    matte_key (desktop chroma UI still colour-key only); Studio look preview
    thumbnails; on-device QA (tracker latency, warp stability under motion,
    Studio slider feel) — needs a phone in hand.
