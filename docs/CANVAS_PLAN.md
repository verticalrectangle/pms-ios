# Canvas system port — direct-manipulation editing on the preview

> Status 2026-07-09 (rev 2): stages 0–6 implemented. Engine emits the transform
> block in `clip_to_json` and engine-smoke round-trips it (Linux gate PASS);
> Swift decodes it end-to-end (EngineProjection → Models.Clip, MockEngine
> parity incl. real begin/end/abort_batch history semantics and a stored
> select_clip selection); `CanvasEditOverlay.swift` carries the whole editing
> surface: tap-to-select with layer cycling, move/scale/rotate handles with
> border/centre/safe-box snapping and 45° rotation stops, crop-edit mode
> (aspect presets, Reset/Cancel/Apply over one abortable batch), text
> move/font-size/wrap gestures through the shared `TextLayoutModel` (also now
> the source of truth for `LayerFeeder.rasterText`, `LyricOverlay`, and export
> rasters — placement fields re-raster on change), safe-zone overlays, and
> flip/reset actions in the clip bar. One gesture = one engine batch = one
> undo entry. **All stage gates ran green (2026-07-10):** Linux engine-smoke
> PASS (incl. the new canvas-transform round-trip + crop-clamp assertions);
> codegen byte-identical; sim builds green after stages 1, 2+3, 4, 5+6;
> xcframework rebuilt on the Mac; unsigned device build green against it;
> `metal-render-test` PASS (109-FX sweep — compositor regression gate).
> Still open: on-device manual gesture QA (real fingers on real Metal), and
> both repos carry these changes uncommitted.
>
> Deviations vs rev 1, all deliberate: crop mode edits over the LIVE cropped
> render with a per-drag frozen reconstruction of the full frame (the desktop
> full-frame crop view is app-side ImGui state the engine knows nothing
> about); text clips get no rotate knob in v1 (their raster is a full-canvas
> layer — rotating it about the canvas centre is not rotating the block);
> body-dragging text forces sub_pos=3 / centre anchor.

## 0. What "the canvas system" is (and what's already here)

On desktop the canvas is two things:

1. **The compositor** — `src/ui/canvas.cpp` Pass 1 drives `scene_begin/add_layer/add_solid/apply_fx/result`
   over `state.tracks` in z-order; Pass 2 draws text via `render_text_block`. **Already ported**:
   `src/metal_render.mm::render_scene` is the Pass-1 track loop (TRACK_LAYERING_PLAN.md, verified by
   `metal-render-test`), and text composites as engine layers via `LayerFeeder` rasters.
2. **The editing surface** — selection handles (move / corner+edge scale / rotate knob), crop-edit
   mode, tap-to-select layer hit-testing, snapping guides, safe-zone overlays, all operating on the
   per-clip transform model. **Not ported at all**: iOS `MetalPreview` has a single tap gesture
   (fullscreen) and `EngineProjection` doesn't even decode the transform fields.

This plan covers item 2 plus the seams item 2 needs (projection fields, mock parity, text-raster
positioning). The compositor side is only touched where verification requires it.

## 1. The desktop model being ported (ground truth, verified 2026-07-09)

- **Per-clip transform** (`src/app.h:205-222`, persisted since project v1, serialized `project.cpp`):
  `pos_x, pos_y` (clip **centre** as fraction of canvas, 0.5/0.5 = centred), `scale_x, scale_y`
  (multiplier on the aspect-fit size), `rotation` (degrees, clockwise), non-destructive crop
  `crop_l/t/r/b` (fractions of the source frame, engine clamps each to `0.95 - opposite`),
  `flip_h/flip_v`. All keyframeable — the canvas reads `eval_prop(prop, playhead)`.
- **Bbox math** (`canvas.cpp:compute_video_bbox`, line 119): aspect-fit the (cropped) source into
  the canvas (`va > ca ? fit to width : fit to height`), then `hw = fit_w * scale_x * 0.5`, centred
  at `pos_* * canvas`. Background clips skip aspect-fit: `hw = w * scale_x * 0.5`.
- **Handles** (`canvas.cpp:draw_canvas_handles`, line 438): `CanvasHandle` = Body drag, 4 corners
  (uniform scale), 4 edges (single-axis scale), Rotate knob floating `ROT_DIST=28px` above the top
  edge, rotating with the clip. Corner/edge handles and the box rotate with `rotation`. Selecting a
  glass FX brick hands the handles to its host video clip.
- **Interaction rules**: body drag snaps the centre to canvas borders/centre (and safe-box edges
  when the social overlay is on); rotate snaps near 45° multiples; drags write props live and push
  **one** history entry per gesture; crop-edit mode (`s_crop`, canvas.cpp:160) replaces the handles
  with a dimmed surround + crop window + aspect presets (free / 1:1 / 9:16 / 16:9) + Reset/Cancel/Apply.
- **Text clips**: bbox comes from the rendered `TextLayout` cache; body drag writes `sub_pos_x/sub_pos_y`
  (+ anchor), corner drag scales `font_size` (a **fraction of canvas height**, never px), edge drag
  writes `sub_wrap_w`.
- **Safe zones**: standard `SAFE_TOP=0.08 / SAFE_BOT=0.20 / SAFE_SIDE=0.05` (`engine_seams.h:28-30`)
  and the social envelope `TABS_T=0.10 / CAP_B=0.22 / RAIL_R=0.12 / SIDE_L=0.08` (`canvas.cpp:49-52`),
  toggled by `show_social_safe`.
- **Agent seam**: the desktop UI publishes `CanvasHandleGeom` each frame (`ui_geom.cpp`) and agents
  read `get_canvas_geometry` + drive `ui_input`. Runtime-only, not serialized.

## 2. Architecture on iOS

Everything is Swift-side except one engine JSON addition (§3). The engine already *renders*
transforms/crop/flips; the app must *edit* them through levers.

- **`EngineProjection.swift`** — decode `pos_x, pos_y, scale_x, scale_y, rotation, crop_l/t/r/b,
  flip_h, flip_v` (+ `sub_pos_x, sub_pos_y, sub_anchor_h, sub_wrap_w` already emitted but dropped)
  into `EngineClipSnapshot`, and carry them onto the UI `Clip` in `uiTracks`.
- **`Models.swift`** — `Clip` gains the transform fields (defaults matching the engine: 0.5/0.5/1/1/0,
  crop 0, flips false).
- **`CanvasEditOverlay.swift` (new)** — the port of `draw_canvas_handles` + hit-testing + gestures,
  a SwiftUI overlay laid out against the same computed `box` as `MetalPreview` (MTKView ignores
  `.aspectRatio`; everything maps view-points ↔ canvas-fractions through `box`). Draws the selection
  box, handles, rotate knob, snapping guides, safe zones, crop mode. Reads the selected clip's
  static transform from the projection (keyframed values: accepted gap, §4).
- **`EditorModel`** — selection already exists (`selectedID`); add a transform-commit path:
  `begin_batch` on gesture start, throttled `set_clip_props` during the drag (**no** `refresh()`
  per tick — the overlay tracks the live value locally; the device engine re-renders from its own
  mutated state), `end_batch` + single `refresh()` on gesture end, so one undo entry per gesture,
  matching desktop. Also mirror selection to the engine via `select_clip` (desktop semantics: the
  canvas selection) whenever `selectedID` resolves to a content clip.
- **`LayerFeeder.rasterText`** — currently hardcodes a centred layout; honor `font_size`
  (fraction-of-canvas-height × height), `sub_pos_x/sub_pos_y`, `sub_wrap_w`, `sub_anchor_h`, and the
  raster key must include those fields so position edits re-submit. The engine composites text
  rasters as full-canvas layers, so text position lives **in the raster**, not in the layer transform.
- **`MockEngine`** — `MClip` gains the same fields; `applyProp` accepts them (with the engine's crop
  clamp); `clipJSON` emits them; `select_clip` stores the selection instead of no-op. Simulator
  stays a faithful contract model.
- **Canvas tap routing** (`EditorView.canvas(box:)`): tap hit-tests content-clip bboxes top-most
  first (desktop click-to-select); a hit selects, a miss keeps today's behavior (fullscreen).
  Handles/gestures only appear while a video/text clip (or glass brick → host) is selected.

## 3. Engine changes (pop-maker-studio)

One JSON-projection gap, no new commands, **no ABI bump** (`pms_command` payload only):

- `src/ipc_server.cpp::clip_to_json` (line 665): emit `pos_x, pos_y, scale_x, scale_y, rotation,
  crop_l, crop_t, crop_r, crop_b, flip_h, flip_v` unconditionally. (`set_clip_prop`/`set_clip_props`
  already accept all of them — lines 2932-2944 / 3093-3107; keyframes already project via `keyframes`.)
- `tools/engine_smoke.cpp`: round-trip assertion — `set_clip_prop pos_x=0.25, crop_l=0.1,
  flip_h=true` then `get_project(verbose)` reflects them.
- `get_canvas_geometry` / `ui_input` stay desktop-only (§4) — on iOS the geometry lives in Swift.

Engine source changed ⇒ Mac xcframework rebuild is required before any device build (memory:
`ssh macbookpro.local 'cd dev/pop-maker-studio && ./scripts/build_xcframework.sh'`).

## 4. Parity gaps accepted in v1 (explicit, not silent)

- **Keyframed transforms**: handles read/write the *static* prop (base value). A clip with transform
  keyframes shows the bbox at the base value, and prop writes behave exactly as desktop prop writes
  do on a keyframed clip. Keyframe-aware handle display (`eval_prop` at playhead) needs keyframe
  evaluation in Swift — deferred with `set_clip_keyframes` UI (FINISH_THE_PORT Slice D).
- **`get_canvas_geometry` / `ui_input` on iOS**: not exposed. The desktop seam exists so agents can
  drive an ImGui surface; iOS agents mutate through `set_clip_props` directly, which is strictly
  more deterministic. If an agent needs the on-screen geometry later, Swift can publish it via a
  new command — engine PR at that time.
- **Alt+click layer cycling**: no Alt on touch. Repeated taps on overlapping bboxes cycle the hit
  stack instead (tap the same point again → next layer down).
- **Camera mirror handles / `MirrorDebugGeom`**: live-mirror face geometry is Slice C/D territory;
  the camera clip still gets plain video handles once it has a take.
- **Background-preset clips**: iOS has no background clips yet (TRACK_LAYERING_PLAN §4 gap); the
  Background bbox branch ports when they land.
- **Snap targets**: canvas borders + centre (+ safe-box edges when overlay on). Desktop's
  other-element alignment guides are not in v1.
- **Crop aspect presets**: same four as desktop (free/1:1/9:16/16:9); no custom ratios, and a
  preset applies once (drags afterwards are free — desktop keeps enforcing the ratio during drags).
- **Crop over the live render**: desktop crop mode shows the clip's FULL frame (app-side ImGui
  render path); the iOS engine has no crop-suspend state, so crop edits apply live and the full
  frame is reconstructed per drag for linear handle mapping. Same values, different in-mode visual.
- **Text rotation**: no rotate knob on text in v1. The text raster is a full-canvas engine layer;
  rotating the layer rotates about the canvas centre, not the block. Needs block-local rastering
  or engine-side text (desktop Pass 2) to do right.
- **Text body drag normalizes placement** to `sub_pos=3` (custom-Y) + centre anchor; left/right
  anchors survive round-trips but any drag re-centres, matching the v1 layout model.

## 5. Decode/interaction budget

- Projection decode: +11 numeric fields per clip — negligible against the existing verbose decode.
- Drag traffic: `set_clip_props` throttled to ≤ 30 Hz per gesture inside a batch; one `refresh()`
  per gesture end (same cost as any timeline mutation today).
- Text rasters: a position/size drag re-rasters at gesture end only (live feedback comes from the
  SwiftUI overlay); no per-frame raster churn.

## 6. Delivery stages & gates

- **Stage 0 — engine projection fields** (pop-maker-studio). `clip_to_json` emits the transform
  block; engine-smoke round-trip added.
  **Gate:** `cmake --build build --target engine-smoke && ./build/engine-smoke` → PASS on Linux.
- **Stage 1 — Swift data plumbing**. `EngineClipSnapshot` + `Clip` carry transforms; `MockEngine`
  parity (props, JSON, `select_clip` stores selection); `EditorModel` mirrors selection via
  `select_clip`.
  **Gate:** sim build green; mock round-trip (set prop → projection shows it) exercised via IPC/dev.
- **Stage 2 — read-only handles**. `CanvasEditOverlay` draws bbox + handles + rotate knob for the
  selected video clip (glass brick → host redirect), aspect-fit bbox math ported from
  `compute_video_bbox`; canvas tap-to-select hit-testing.
  **Gate:** sim build green; selecting a timeline clip shows a correctly placed box on the canvas.
- **Stage 3 — transform gestures**. Body drag (with border/centre snapping), corner uniform scale,
  edge single-axis scale, rotate knob (45° snapping); batched commit path (`begin_batch` /
  throttled `set_clip_props` / `end_batch` + refresh) = one undo entry per gesture.
  **Gate:** sim build green; drag/scale/rotate round-trip through the mock, single undo undoes a
  whole gesture.
- **Stage 4 — crop-edit mode**. Dimmed surround + crop window + 8 drag handles + body pan, aspect
  presets, Reset/Cancel/Apply; entered from the clip action bar.
  **Gate:** sim build green; crop values clamp exactly like the engine (`0 … 0.95 - opposite`).
- **Stage 5 — text on canvas**. `rasterText` honors `font_size`/`sub_pos_*`/`sub_wrap_w`/anchor;
  text clips get body drag (sub_pos), corner font-size drag, edge wrap-width drag; raster re-submits
  on commit.
  **Gate:** sim build green; moving a title updates the raster layout (mock: prop round-trip;
  device: visible).
- **Stage 6 — safe zones + polish**. Standard + social safe-zone overlays (toggle in the canvas
  chrome), flip_h/flip_v + reset-transform actions in the inspector/action bar.
  **Gate:** sim build green.
- **Stage 7 — proof on real toolchains**. Rsync both repos to macbookpro.local; rebuild the
  xcframework (engine changed in Stage 0); `xcodegen` + sim build + unsigned device build;
  `metal-render-test` still passes (compositor untouched, this is the regression gate).
  **Gate:** all three Mac gates green; Linux engine-smoke green at the final engine commit.

## 7. Definition of done

- A selected video clip shows desktop-equivalent handles on the preview; move/scale/rotate/crop/flip
  all commit through `pms_command` levers, survive save/load, and undo one gesture at a time.
- Titles are position/size-editable on the canvas and the committed raster matches (preview == export
  path unchanged: rasters composite engine-side).
- The transform state round-trips: engine → projection → UI → lever → engine, byte-stable fields.
- Every stage gate ran; gaps are the §4 list, nothing else.
