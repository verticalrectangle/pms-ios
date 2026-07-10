# RECORD_PLAN — full-screen camera recording with live looks

Status: rev 1 (2026-07-10). Execution in progress; per-stage gate results appended as they land.

## Goal

An Instagram/TikTok-grade record mode: tap Record, the camera fills the screen,
a swipeable rail of *looks* (makeup, color grades, trippy, cyberpunk, Chroma FX)
applies in real time through the real engine renderer, and the finished take
lands on the timeline with the look attached as ordinary FX bricks — editable,
export-baked, and identical on desktop. Everything filter-shaped is implemented
**engine-side** (registry GLSL → transpiled MSL, or hand-written Metal passes),
so every look is automatically available in the desktop Pop Maker Studio app
too, and every desktop effect — including the legacy Chroma FX family — becomes
available on iOS. No iOS-only shader forks.

## Where we start (verified 2026-07-10)

What already exists and is reused as-is:

- `CameraCapture.swift` — full AVCaptureSession: 720×1280 BGRA video +
  mic → engine (`pms_submit_camera_frame` / `pms_submit_mic_block`),
  front/back `position` param, connection-level rotation + front mirroring,
  AVAssetWriter take sink (H.264 + AAC .mov), Vision person matte ≤15 fps.
- `MetalPreview.swift` — MTKView; `store.render` → engine `pms_render`;
  preview pixels == export pixels.
- `set_live_fx` — ordered FX stack, per-entry `params` + `amount` wet/dry +
  `[start,end)` window (defaults ±1e30 = always on). Runner:
  `metal_render.mm run_fx_stack` (ping-pong, per-entry status, never silent).
- Effect catalog codegen: `effects/registry.json` → `codegen_effects.py` →
  23 generated headers + `effects/mcp_manifest.json` → pms-ios
  `gen_effect_catalog.py` → `GeneratedEffectCatalog.swift`; GLSL →
  `transpile_shaders.py` (glslang + spirv-cross) → `Shaders/msl/*.metal` +
  `params_manifest.json`.
- Take landing: `EditorModel.placeBinItem(path)` adds the .mov as a clip at
  the playhead.

The gaps this plan closes:

1. **No full-screen record surface.** Camera previews inside the ~40% editor
   canvas; `FullscreenPlayer` is playback-only and pauses MetalPreview.
2. **No record-time filter picker.** Live FX are derived from timeline bricks
   (`syncLiveFX`), span-windowed to brick times.
3. **Chroma FX parity hole.** The desktop Chroma family (Chroma Key / Melt /
   Echo / Frame) plus legacy Grade/Blur/Vignette/VHS/Glitch/ZoomPunch/LightLeak
   are hand-wired GLSL in `fx_shader.cpp` — not in the registry, no MSL →
   `unknown_fx` on iOS, and absent from the iOS catalog.
4. **No Makeup / Trippy / Cyberpunk families.** Closest existing: Beauty (4),
   `cyberpunk_grade`, assorted Color/Glitch/Warp effects.
5. Camera hardwired to `.back` at the EditorView call site; no flip UI.

Cross-platform note: the iOS catalog is *generated from* the desktop manifest,
so "all app FX accessible in Pop Maker Studio" is satisfied by construction as
long as new work goes into the registry / engine — which is the rule this plan
follows. The one direction that needs real work is desktop → iOS (the legacy
family), which is Stage 1.

## Stage 0 — toolchain

`spirv-cross` is not packaged on this Linux box and sudo is unavailable; built
from source into the job dir and passed to `transpile_shaders.py` via
`--spirv-cross`. glslangValidator is system-installed. Mac has neither — all
transpiles run on Linux (outputs are checked-in .metal files, so the Mac only
compiles them).

## Stage 1 — Chroma FX (and friends) on Metal/iOS

### 1a. Stateless legacy FX → transpiled MSL

`chroma_key`, `grade`, `blur`, `vignette`, `glitch`, `zoom_punch`,
`light_leak`, `vhs` are single-pass, stateless fragment shaders. Plan:

- Extract each `k_*_frag` from `src/fx_shader.cpp` into
  `shaders/legacy/<fx>.glsl` (header comment: fx_shader.cpp stays the desktop
  source of truth; these are transpile sources — keep in sync).
  `textureSize()` is legal here (Vulkan glslang), but normalize to
  `u_tex_w/u_tex_h` where trivial for consistency.
- Transpile → `pms-ios/Shaders/msl/<fx>.metal` + `params_manifest.json`
  entries keyed by the live-FX names the engine already uses
  (`chroma_key`, `grade`, … — see `metal_render.mm fxtype_name`).
- Uniform names in the manifest must match the param keys that arrive in
  `set_live_fx` entries (short names, e.g. `threshold`, `persist` — verify
  against what `clip_to_json` emits for legacy `fx_chain` params and align).
- LUT stays desktop-only (needs a LUT texture upload path); Datamosh is
  stateful → grouped with 1b or deferred.

### 1b. Stateful Chroma feedback passes (hand-written Metal)

`chroma_melt` / `chroma_echo` (single persistent feedback texture) and
`chroma_frame` (8-deep snapshot ring + head/taps/spacing) cannot be flat
manifest PSOs. Plan, modeled on the existing body-FX pass table:

- Hand-write MSL for the three passes in `metal_render.mm` (source: the GLSL
  in `fx_shader.cpp:272-380`).
- Add a small per-*stack-entry* state table: feedback texture (melt/echo),
  ring array texture + head index + last-snapshot time (frame). Keyed by
  stack index + fx_type; reallocated on resolution change; cleared when the
  stack entry disappears.
- `run_fx_stack` gains a branch for these three names before the manifest
  lookup; after the pass, blit the output into the feedback slot (melt/echo)
  or snapshot into the ring at `spacing` cadence (frame). Status strings as
  usual.
- Gate: extend `tools/metal_render_test.mm` — render N frames with a moving
  gradient under each chroma pass and assert temporal accumulation (frame N
  pixel differs from a single-frame render; melt trail decays with persist).

### 1c. Catalog exposure

- `codegen_effects.py` gains a hand-authored `LEGACY_MANIFEST_EXTRAS` table
  appended to `mcp_manifest.json`: the four Chroma FX under a new category
  **"Chroma"**, and the graded legacy set (grade/blur/vignette/vhs/glitch/
  zoom_punch/light_leak) under their natural categories. Desktop UI is
  untouched (it already has cards for all of these); the manifest is the
  MCP/iOS surface.
- Verify `set_clip_fx` / `add_effect_brick` accept these fx ids with the
  manifest param names (engine already maps `"chroma_melt"` →
  `FXType::ChromaMelt`; param key routing may need a shim in
  `ipc_server.cpp`).
- Regen `GeneratedEffectCatalog.swift` → the Chroma family appears in the
  iOS FX sheet + record rail with zero Swift changes.

## Stage 2 — new look families (registry effects, both platforms)

New data-driven registry effects — GLSL 330, no state, transpile clean. These
are full-frame "look" shaders (honest scope: no face-landmark warps; the
desktop face_filters/MediaPipe stack is a separate, later port — noted in
FINISH_THE_PORT.md).

| Category | id | What it is |
|---|---|---|
| Makeup | `porcelain_skin` | bilateral-ish luma smooth + brighten + even tone |
| Makeup | `blush_doll` | cheek-zone warm blush wash + eye brighten + soft bloom |
| Makeup | `honey_glow` | golden-hour warmth + glow + gentle contrast lift |
| Makeup | `soft_glam` | smooth + teal-shadow/warm-highlight split tone + sparkle |
| Trippy | `acid_trip` | time-cycling hue rotation + sine UV wobble |
| Trippy | `liquid_marble` | flowing domain-warped marble refraction |
| Trippy | `fractal_mirror` | recursive kaleido fold with zoom drift |
| Trippy | `breathe_warp` | slow radial breathing zoom + chroma offset |
| Trippy | `melt_drip` | downward smear columns, heat-haze melt (stateless) |
| Cyberpunk | `neon_city` | teal/magenta grade + scanlines + bloom streaks |
| Cyberpunk | `chrome_pulse` | metallic spec curve + pulsing edge glow |
| Cyberpunk | `hud_glitch` | HUD frame lines + digital block dropouts + cyan tint |
| Cyberpunk | `night_drive` | dark blue-hour grade + sodium highlights + anamorphic flare |

- Registry entries with params (intensity-style first param each so the record
  rail's one slider maps naturally), `since_version` bump, new categories
  `Makeup`, `Trippy`, `Cyberpunk`.
- Desktop: add the three categories to `g_fx_categories[]` in
  `src/ui/panel_fx.cpp` so they get their own pills (else "Other").
- Pipeline: codegen → build + engine-smoke on Linux → transpile → catalog
  regen (byte-identical rule for the two generators on re-run).

## Stage 3 — the Record experience (iOS)

New `RecordView.swift`, presented as `fullScreenCover` from EditorView (toolbar
record button replaces the in-canvas record dot) and from HomeView ("Record"
quick action → opens a new project into the editor with RecordView up).

Layout (TikTok-shaped):

- Full-bleed `MetalPreview` (unpaused, `store` live) — the engine renders the
  camera frame through the live FX stack, so what you see is exactly what
  exports.
- Right rail: flip camera (front default), matte toggle (auto-on when a look
  uses body FX), flash placeholder, timer (3s/10s countdown).
- Bottom: category tabs (**For You · Makeup · Color · Trippy · Cyberpunk ·
  Chroma · Body**) over a horizontally swipeable look carousel (circular
  thumbnails, name under the active one, haptic on change); "no filter" is
  always slot 0. One vertical slider = look intensity (drives the stack's
  `amount`).
- Center-bottom: record button — tap to start/stop, ring shows elapsed;
  recording state pauses look switching? No — switching mid-record is allowed
  (the landed bricks reflect the *segments*: v1 keeps it simple and bakes the
  look active at stop; segment-accurate bricks are a stretch goal).

Plumbing:

- `FilterLooks.swift` — curated preset table: each look = ordered
  `[[fx_type, params]]` (1–3 entries; e.g. Cyber Neon = `neon_city` +
  `chromatic_aberration(1.5px)`; Chroma Melt look = `chroma_melt` with green
  key). Looks reference only catalog fx ids — asserted against
  `EffectCatalog.byID` in debug.
- Record-scoped live stack: RecordView pushes `set_live_fx` directly with the
  look's stack (no `start`/`end` → always on), bypassing timeline-derived
  `syncLiveFX`; on dismiss it calls `model.syncLiveFX()` to restore timeline
  truth.
- Camera: reuse `CameraCapture`; default `.front`; flip = stop/start with the
  other position (session reconfig, <300 ms).
- Take completion: `stopTake` → `placeBinItem(url)` → auto-apply the active
  look as coupled FX bricks over the new clip's span (same
  `add_effect_brick`/`add_multifx_brick` path as FXSheet), so the take plays
  back and exports with the look, still fully editable. The recorded .mov
  stays clean (raw sensor) — filters are non-destructive by design.
- `MockEngine`: accept `set_live_fx` (store the stack, echo in `fx_debug`)
  so the simulator flow is drivable.

## Stage 4 — proof gates (per pms-port-build-workflow)

1. Linux: `cmake --build build --target engine-smoke && ./build/engine-smoke`
   → PASS; codegen + gen_effect_catalog byte-identical on second run.
2. rsync both repos → macbookpro.local.
3. Mac: `./scripts/build_xcframework.sh` (engine sources changed).
4. Mac: `xcodegen generate` + sim build (ENGINE_MOCK) + device build.
5. Mac: metal-render-test — PSO sweep now covers manifest + legacy entries;
   new chroma feedback assertions green.
6. Docs: FINISH_THE_PORT.md addendum + this file's status updated; memory
   updated.

## Non-goals / deferred

- Face-landmark makeup (MediaPipe 478-pt warp/`MakeupLook`) — desktop-only
  today; porting the face stack to iOS is its own plan (model download flow,
  ONNX runtime session, Metal warp pass).
- Baking filters into the recorded .mov file itself (takes stay raw +
  non-destructive bricks; a "flatten" is just the existing export).
- Segment-accurate mid-record look switches (v1 bakes the look active at stop).
- LUT effect on iOS (needs LUT texture upload path).
- Body-FX Metal coverage beyond the existing 3 passes.

## Status log

- 2026-07-10: plan written; Stage 0 done (spirv-cross built from source).
- 2026-07-10 (later, same session): **all stages executed, all gates green.**
  - Stage 1a: 8 legacy transpile sources in `shaders/legacy/` (grade, blur,
    vignette, chroma_key, glitch, vhs, light_leak, datamosh) — uniform names =
    fx_chain param keys, px→UV conversions moved in-shader; blur is a one-pass
    24-tap disc (documented deviation from the desktop 2-pass box). zoom_punch
    dropped from 1a (CPU transform, like ken_burns); LUT deferred.
  - Stage 1b: `metal_render.mm` — kChromaSrc MSL (melt/echo/frame), per-chain
    feedback state `g_chroma_fb` keyed (chain_id, stack idx, fx_type), ring
    snapshots on the scene clock with scrub reset, GC every 64 frames /
    600-frame TTL. `run_fx_stack` gained `chain_id` (glass = track<<12|clip,
    bus = -(track+16), camera = -2). Also fixed: `scene_push_fx` now emits
    params for ALL legacy FXTypes (they were silently param-less on Metal).
  - Stage 1c: codegen appends `LEGACY_MANIFEST_EXTRAS` (11 entries, Chroma
    category for the keyed family) → manifest 133 effects; `agent_tools.h`
    regenerated (build gate enforces it).
  - Stage 2: 13 new registry effects (Makeup 4 / Trippy 5 / Cyberpunk 4),
    registry v25, desktop category pills updated; 129 shaders transpile clean.
  - Stage 3: `RecordView.swift` (full-screen capture, category rail + look
    carousel, intensity = wet/dry, front default + flip, 3s timer, elapsed
    badge), `FilterLooks.swift` (30+ curated looks, catalog-checked),
    `EditorModel.placeRecordedTake` (take + coupled Multi-FX look brick),
    Home camera quick-action → editor with RecordView up; old in-canvas
    camera/record path removed from EditorView.
  - Stage 4 gates: Linux full build + engine-smoke PASS; codegen + catalog
    byte-identical on rerun; Mac `metal-render-test` **PASS** including the
    new `k.legacy_fx` (8/8 visible) and `l.chroma_feedback` (temporal ghosts
    persist for melt/echo/frame) cases + 122-effect PSO sweep; xcframework
    rebuilt; sim (ENGINE_MOCK) and device (iphoneos26.2) builds SUCCEEDED.
  - Not yet done: on-device manual QA of the record flow (gestures, camera
    flip latency, look switching under load); §4 stretch goals (segment-
    accurate mid-record look bricks, LUT upload, face-landmark makeup).
