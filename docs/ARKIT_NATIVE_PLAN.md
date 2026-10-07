# ARKit makeup — architecture

Rebuilt 2026-10-07. Makeup renders only on the TrueDepth front camera, on
ARKit's own face mesh, drawn with ARKit's own camera from the same ARFrame as
the pixels. The rear camera and non-TrueDepth devices show no makeup (the
record screen says so); there is no MediaPipe makeup tier on iOS any more.

## Data flow

1. **Capture** — `App/Sources/ARKitCameraCapture.swift`, per ARFrame:
   the portrait BGRA frame (`pms_submit_camera_frame`), then the face
   (`pms_submit_arkit_face_3d`): anchor-space vertices (meters), anchor /
   view / portrait projection matrices, blendshapes (MediaPipe order), and the
   frame's `ARDirectionalLightEstimate` (primary light direction + intensity,
   spherical harmonics, ambient intensity/temperature). One tracked face.
   Untracked → the slot clears; a face older than 0.15 s of camera time is
   never drawn (`src/arkit_face.cpp`).
2. **Look selection** — `FilterLooks.swift`: a makeup look is one `face_fx`
   stack entry `{face_look: "<id>", params: {face_amount}}`; the record
   intensity slider is `face_amount` (1 = as designed, up to 2).
3. **Render** — engine `src/arkit_makeup.mm`, called by the FX runner:

   | Pass | Resolution | What |
   |---|---|---|
   | prep | half, mesh | linear camera color × skin mask × facing, premultiplied |
   | blur | half, 2× separable | mask-normalized bilateral → local skin color; 1×1 mip = face-mean skin |
   | face | full, mesh, depth | skin finish, pigment layers, lips, 3D liner, gloss/highlighter |
   | lashes | full, depth-tested | strand ribbons, premultiplied over |

4. **Recording** — `FilteredTakeRecorder` re-renders every frame through the
   engine, so the look is baked into the take's pixels; takes never carry a
   `face_fx` brick (no double application on the timeline).

## Pigment model

Every color in a look is authored as *how it reads on the look's reference
skin* (sampled from the reference photo). A layer is the per-channel
transmittance `T = lin(color) / lin(reference_skin)` applied Beer–Lambert
style in linear light: `c *= T^(coverage · amount)`. The camera's own
lighting, pores and shading survive because pigment only filters the light
that is already there, and every skin tone keeps its own depth. Lip cream
and liner ink use the same ratio over the local skin color (opaque); gloss
and highlighter add light — GGX specular from ARKit's primary light on the
mesh normals, scaled by the local skin irradiance.

- **Skin**: smoothing radius is in millimetres on the face (`smooth_mm`),
  converted to pixels from the projection each frame; the skin mask excludes
  eyes, brows, lips and fades at the mesh boundary.
- **Liner**: no texture. Per fragment, the true 3D distance to the live
  upper-rim polyline (12 vertices, outer → inner) plus a tapered wing stroke
  projected onto the outer corner's tangent plane; widths in millimetres,
  antialiased by the fragment's footprint.
- **Lashes**: 6-segment strands generated per frame from the rim polylines
  and their surface frame (normal, along-lid direction): lift, curl toward
  the lid, outer flare, wispy clumps; drawn ≥1 px wide with coverage = true
  width, so sub-pixel strands darken by exactly their area.
- **Brows**: hair-aware — darkens pixels clearly darker than the surrounding
  skin inside a generous brow region (painted brow shapes never match real
  brows), plus a faint fill.

## A look is data

`Engine/EngineAssets/models/face/arkit/<id>.json` + two mask atlases.

| Key | Fields |
|---|---|
| `masks` | `[<id>_a.png, <id>_b.png]` |
| `reference_skin` | `#rrggbb` the colors were matched on |
| `skin` | `smooth`, `smooth_mm`, `even`, `lift` |
| `blush`, `shadow`, `freckles` | `color`, `amount` |
| `brows` | `color`, `amount`, `fill` |
| `inner_light` | amount |
| `lips` | `color`, `cover`, `overline_mm`, `edge_mm`, `gloss`, `roughness` |
| `highlight` | `amount`, `roughness`, `sheen` |
| `liner` | `color`, `amount`, `inner_mm`, `outer_mm`, `wing_mm`, `wing_lift_deg`, `offset_mm` |
| `lashes` | `color`, `amount`, `upper` / `lower`: `count`, `clumps`, `len_inner_mm`, `len_outer_mm`, `root_mm`, `lift_deg`, `curl_deg`, `flare`, `wisp`, `clump`, `offset_mm`, `t0`, `t1`, `blink_close` |

Masks (ARKit UV; texel row = v · size):

| Atlas | Size | r | g | b | a |
|---|---|---|---|---|---|
| `_a` | 1024² | skin (smoothing) | blush | eyeshadow | brow region |
| `_b` | 2048² | lip SDF `0.5 + d/16` (mm, − inside) | freckles | gloss / highlighter | inner-corner light |

Masks are geometry only, baked by engine `tools/gen_arkit_makeup.py` on the
canonical ARKit head in millimetres and padded past their UV islands for
mipmapping. Topology facts it relies on: the eye-hole rims are the lash
lines (upper rims 1101→1090 and 1069→1080); the 36-vertex loops around the
mouth hole are the lip anatomy — loop 3 traces the vermilion border and its
upper half carries the cupid's bow. Colors and amounts retune live in the
JSON without rebaking.

## QA

Engine repo `docs/ARKIT_REPLAY_QA.md`: triple-tap in the record screen
records 10 s of real frames + geometry + light; `arkit-native-replay` renders
any look onto those exact frames on the Mac. `scripts/build_mac.sh --run`
runs the synthetic gate (placement, blink, yaw, overlay, missing-look status).
The `face_overlay` command draws the mesh as a UV checker with the live lash
line for on-device alignment checks.

## History

- 2026-07-12: a 2D bridge (ARKit mesh → screen → 478 MediaPipe landmarks)
  failed eight rounds of on-device QA; replaced by rendering ARKit's own mesh
  in 3D.
- 2026-07 → 09: per-look RGBA decal atlases on that mesh. By October 34 of
  35 makeup looks had no atlas left (front camera showed skin smoothing
  only), lashes were env-gated off, the 3D liner quads were degenerate
  (both axes along the rim), blending ran in gamma space, and a
  color-deviation "occlusion" gate faded lipstick off real lips. Every look,
  plate, the Makeup Studio, the MediaPipe makeup tier and the 2D bridge were
  deleted on 2026-10-07 in favor of the system above.
