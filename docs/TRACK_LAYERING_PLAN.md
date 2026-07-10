# Track layering on iOS — desktop-parity plan

> **Status 2026-07-09:** Stages 0–4 are implemented and build-proven (Linux
> engine-smoke PASS at ABI 3; xcframework compiles clean; simulator + unsigned
> device builds green). GPU behavior is **not yet device-verified** — the §7
> definition-of-done scenario needs a phone. Known deviations recorded in
> `fx_debug` statuses: hand-written desktop FX (grade/blur/vignette/…) have no
> MSL ports and report `unknown_fx`; beat-pulse FX modulation, ZoomPunch/
> datamosh CPU paths, background presets, and per-clip body-FX masks remain
> the accepted v1 gaps of §4.

**Goal.** The canvas composites exactly like the desktop app: the bottom
timeline track is the bottom layer of the canvas and every track above stacks
over it, with the whole brick system behaving identically. Reference
implementation: `pop-maker-studio/src/ui/canvas.cpp` (preview) and
`src/render.cpp` (export) — both run the same loop, which is the parity
contract this plan ports.

## 1. The desktop model being ported (ground truth, verified 2026-07-09)

One scene target; tracks iterated `ti = tracks.size()-1 … 0` (bottom lane
first = deepest layer; track 0 = frontmost). Per track, in order:

1. **Background clip** active at t → rendered with keyframed transform/opacity,
   layered over the scene.
2. **Video-like clip** (video / image / take / camera brick) active at t:
   - decode texture → **glass FX** (Effect/MultiFX bricks on the same track
     that are *coupled* to this clip — `fx_clip_is_glass`) applied to the
     clip's pixels only → **glass Body FX** (host clip's own mask sequence;
     RemoveBackground at most once) → runtime FX → face filter;
   - placed into the scene with keyframed `pos/scale/rotation/opacity`
     (`eval_prop`), crop as a UV window, `flip_h/v`, aspect-fit;
   - **transitions** (dissolve / fade-black / dip-white) draw outgoing +
     incoming clips with computed alphas across the cut.
3. **Text/lyrics/subtitles on this track** composite into the scene at this
   z-order — higher tracks occlude lower text.
4. **Uncoupled Effect/MultiFX bricks on this track = group bus**: they process
   the *accumulated composite so far* (everything below + this track), gated
   by the brick's span. "Global FX" is not a GFX-rail special case — any free
   brick filters everything beneath its track position; the GFX rail is just
   an empty top track. Decoupling (which lifts a brick to a fresh track below
   the content) is what changes *what it applies to*.

Audio tracks never enter the scene loop (sound only).

## 2. Architecture on iOS

The engine already owns `AppState` (tracks, coupling, keyframes, transitions)
on iOS. What it cannot own is decode. Division:

- **Swift (layer feeder)** — for every *visual* layer active at the playhead,
  produce a BGRA texture-ready buffer each frame and submit it addressed by
  engine `(track, clip)`:
  - video layers: AVFoundation decode (base track = the existing AVPlayer
    master clock; overlay video tracks = additional players/outputs synced to
    the transport, capped — see §5);
  - text layers: CoreGraphics raster of the styled string (transparent RGBA),
    re-submitted only when content/size changes;
  - camera layers: the live capture feed (already submitted today).
- **Engine Metal renderer (scene compositor)** — `pms_render` stops being
  "background + one content frame + flat FX list" and instead walks
  `state.tracks` bottom→top exactly like the desktop loop: layer transform
  quads (eval_prop, crop UVs, flips, opacity, aspect-fit), per-layer glass FX
  chains (the existing generated-MSL runner, refactored to run on any input
  texture), matte body passes per layer, transition alphas, per-track bus FX
  applied to the accumulated target. `set_live_fx` (the flat adapter) is
  retired — the renderer derives everything from `AppState`, which was the
  port doc's stated end state.
- **Export** — unchanged shell (AVAssetReader/Writer), but per output frame it
  submits *every* layer's frame for that time (per-source readers stepped at
  output fps + text rasters) and runs the same `pms_render`. Preview == export
  because both are the same engine loop, mirroring the desktop guarantee.
- **Audio** — all audio-carrying clips still flatten into the AVComposition
  mix for playback/export; the visual stack ignores them (desktop parity).

## 3. ABI / engine changes (ABI 3)

```c
// Submit one visual layer's frame for the CURRENT render, addressed by engine
// clip identity. BGRA CVPixelBuffer; the engine retains until superseded.
// text/overlay layers may be submitted once and persist until replaced or
// cleared (pass NULL to clear). Rotation as quarter turns (camera parity).
void pms_submit_layer_frame(pms_engine*, int track, int clip,
                            void* cv_pixel_buffer_bgra,
                            int rotation_quarter_turns,
                            double host_time_seconds);
#define PMS_ENGINE_ABI 3
```

- `pms_submit_camera_frame` stays (live camera + single-content fallback);
  when any layer frames are present the scene loop wins.
- New `move_track` IPC handler: `{from, to}` reorders `state.tracks`
  (selection/coupling indices fixed up, one history step) — required by the
  reorder gesture and absent today.
- Renderer reads `AppState` under the same lock discipline as `pms_tick`
  (both are main-thread on iOS; export pauses ticks — existing contract).
- `fx_debug` reports the scene path: layers drawn, glass/bus applications,
  transitions taken, skipped (no-frame) layers.

## 4. Parity gaps accepted in v1 (explicit, not silent)

- **Background preset clips**: the desktop's procedural GL backgrounds aren't
  ported yet; a Background clip renders as the engine's aurora. Listed in
  `fx_debug`; UI doesn't offer bg presets yet anyway.
- **Body FX masks for timeline clips**: desktop uses per-clip precomputed mask
  dirs (`start_bg_remove`). iOS v1 uses the live Vision matte (camera) only;
  an offline Vision mask pass per imported clip is the follow-up. Body passes
  on non-camera layers no-op without a matte (reported in fx_debug).
- **Face filters, datamosh/ZoomPunch CPU paths, runtime hot-reload FX**: not
  in the iOS renderer yet (desktop-only subsystems).
- **Simulator**: ENGINE_MOCK has no renderer; layering is device-proven.

## 5. Decode budget

Simultaneous *video* layers are capped at 3 (base + 2 overlays) — each is a
full decoder. Text/camera layers are cheap and uncapped. Beyond-cap video
layers are skipped bottom-up and reported via `fx_debug`/`lastError` rather
than silently dropped.

## 6. Delivery stages & gates

- **Stage 0 — engine lever**: `move_track` handler + engine-smoke coverage
  (reorder, index fixups, undo). Gate: Linux smoke PASS.
- **Stage 1 — Metal scene compositor**: layer store keyed by (track, clip),
  scene loop (transforms/crop/flip/opacity, glass FX per layer, bus FX per
  track, matte body passes, transitions, text layers as submitted rasters),
  `set_live_fx` retired, ABI 3. Gate: xcframework build; Linux build/smoke
  stay green (Metal not compiled there); fx_debug shows the scene path.
- **Stage 2 — Swift layer feeder (preview)**: per-track frame sources (base
  AVPlayer + overlay outputs + text rasters + camera), submissions keyed by
  current projection addresses each frame; titles removed from the played
  AVComposition (they become engine layers); syncLiveFX deleted. Gate: sim +
  device builds; manual device check.
- **Stage 3 — export parity**: per-layer readers stepped at output fps feed
  the same submissions per frame; writer shell unchanged. Gate: device
  export of a layered project matches preview.
- **Stage 4 — UI**: drag a track header up/down → `move_track`; timeline
  already renders lanes in track order. Gate: builds; reorder round-trips
  through save/load.

## 7. Definition of done

Two overlapping video tracks + a text track + a free FX brick mid-stack render
on device with: lower track behind upper, text occluded by video above it,
the free brick filtering only what's below it, a coupled brick filtering only
its host clip, preview == export, and the ordering surviving save → reload →
desktop open.
