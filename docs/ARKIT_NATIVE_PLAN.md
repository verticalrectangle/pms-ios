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
   | prep | half, mesh, 2 targets | linear camera color × skin mask × facing, premultiplied; lip core → 1×1 mip = mean lip color |
   | blur | half, 2× separable | mask-normalized bilateral → local skin color; 1×1 mip = face-mean skin |
   | lipev | half, mesh | lip evidence: redness of a ~6 px averaged color over the local skin |
   | lidcrop | 256², fullscreen | roll-normalized face crop for MediaPipe's landmark model (worker thread, below) |
   | face | full, mesh, depth | skin finish, pigment layers, lips, 3D liner, gloss/highlighter |
   | lashes | full, depth-tested | strand ribbons, premultiplied over |

4. **Recording** — `FilteredTakeRecorder` re-renders every frame through the
   engine, so the look is baked into the take's pixels; takes never carry a
   `face_fx` brick (no double application on the timeline).

## Pigment model

Every translucent color in a look is authored as *how it reads on the look's
reference skin* (sampled from the reference photo). A layer is the
per-channel transmittance `T = lin(color) / lin(reference_skin)` applied
Beer–Lambert style in linear light: `c *= T^(coverage · amount)`. The
camera's own lighting, pores and shading survive because pigment only filters
the light that is already there, and every skin tone keeps its own depth.
Liner ink uses the same ratio over the local skin color (opaque). Gloss and
highlighter add light: GGX specular from ARKit's primary light plus a soft
frontal key above the camera (selfie shine mirrors the screen and the room in
front), scaled by the local skin irradiance.

- **Skin**: smoothing radius is in millimetres on the face (`smooth_mm`),
  converted to pixels from the projection each frame; the skin mask excludes
  eyes, brows, lips and fades at the mesh boundary.
- **Lips**: the canonical mouth loops are not every wearer's lips (on a real
  capture the vermilion border sat a loop and more inside ARKit's), so the
  mesh only bounds the region (canonical border + 3 mm) and marks the deep
  lip core; where the lips are comes from the camera — lip tissue is redder
  than the surrounding skin. The evidence is dilated by `overline_mm`, and the
  core always counts so low-contrast lips still get color. Lipstick is opaque
  and absolute: the product color, its brightness pulled toward the wearer's
  mean lip brightness by `1 − match`, re-lit by the lips' own shading
  relative to that mean (volume, creases, real highlights survive; overlined
  skin gets flat product color). Gloss rides the same coverage, broken up by
  the lips' texture. The mouth hole has no mesh, so teeth and tongue are
  never painted.
- **Lash lines**: ARKit's eye rims are the lash lines only with the eyes
  wide open. With the lids lowered (gaze down at the phone, the normal
  selfie pose) the real upper lid is flatter than ARKit's almond — the rim
  rides ~2 mm onto the lid over the iris and sits inside the eye toward the
  outer corner — the lower rim sits inside the eye opening, and ARKit's
  blink value stays low through all of it. Image edge rules cannot fix it:
  with the eyes open the natural lashes stand above the margin, lowered they
  hang over the eye, so "where the lid skin ends" is the margin in one pose
  and the lash tips in the other. The trained lid contours of MediaPipe's
  landmark model (`models/face/face_landmarks_v2.onnx`, already bundled for
  the script API) decide: up to 30 times a second a 256² roll-normalized
  face crop, placed from ARKit's projected mesh (no detector), goes to a
  worker thread; each lid contour is intersected with 16 rays cast from that
  frame's ARKit rim, the offsets get a quadratic fit along the rim (the real
  lid differs from ARKit's smoothly; kinks fit badly) and a trust from the
  fit residual and how squarely the eye faces the camera (turned eyes are
  foreshortened). Later frames apply them relative to their own rims (head
  motion stays ARKit's) with adaptive smoothing (the net jitters ±0.5 mm). No
  blink fade: half-lowered lids are exactly where the correction matters.
  The upper offsets move the liner and upper lash roots, the lower ones the
  lower roots. The replay runs the worker synchronously (`PMS_ARKIT_SYNC`)
  so PNGs are deterministic; the first frame of a capture has no result yet.
- **Lid frame**: "along the lid, away from the opening" is oriented by the
  opposite rim at the same rim parameter (plus a fixed bias where the rims
  meet at the corners). Orienting by the eye center flipped it along the rim
  of a nearly closed eye — the center sits on the rims — and the eyelid
  offsets then threw liner and lash roots millimetres the wrong way.
- **Liner**: no texture. One centerline per eye: the upper lash line from the
  inner corner to just short of the outer corner, lifted half a stroke onto
  the lid (the ink's lower edge sits on the lash line), continued by a
  quadratic wing that leaves in the lash line's direction — one stroke, so
  band and wing never cross. Per fragment: signed distance to the
  variable-width stroke (3D on the lid, the outer corner's tangent plane for
  the wing); widths in millimetres, antialiased by the fragment's footprint.
- **Lashes**: 6-segment strands generated per frame from the rim polylines
  and their lid frame: lift, curl toward the lid, outer flare, wispy clumps;
  roots sit on the eyelid-corrected lash lines. Lower lashes thin out as the
  real opening (ARKit's, closed by both lid corrections) drops below ~5 mm:
  on a closed eye they hide under the upper fringe, drawn they smudge. Drawn
  ≥1 px wide with coverage = true width, so sub-pixel strands darken by
  exactly their area. Falsies read as a dense fringe heaviest at the root:
  long, strongly curled strands project up the lid as hooks in a selfie view.
- **Brows** stay the wearer's own: a region painted on the canonical head
  never matches real brows (it read as drawn-on blocks on a real face).

## A look is data

`Engine/EngineAssets/models/face/arkit/<id>.json` + two mask atlases.

| Key | Fields |
|---|---|
| `masks` | `[<id>_a.png, <id>_b.png]` |
| `reference_skin` | `#rrggbb` the colors were matched on |
| `skin` | `smooth`, `smooth_mm`, `even`, `lift` |
| `blush`, `shadow`, `freckles` | `color`, `amount` |
| `inner_light` | amount |
| `lips` | `color` (absolute, as on the reference face), `cover`, `overline_mm`, `match` (0–1, product vs. own lip brightness), `gloss`, `roughness` |
| `highlight` | `amount`, `roughness`, `sheen` |
| `liner` | `color`, `amount`, `inner_mm`, `outer_mm`, `wing_mm`, `wing_lift_deg`, `offset_mm` |
| `lashes` | `color`, `amount`, `upper` / `lower`: `count`, `clumps`, `len_inner_mm`, `len_outer_mm`, `root_mm`, `lift_deg`, `curl_deg`, `flare`, `wisp`, `clump`, `offset_mm`, `t0`, `t1`, `blink_close` |

Masks (ARKit UV; texel row = v · size):

| Atlas | Size | r | g | b | a |
|---|---|---|---|---|---|
| `_a` | 1024² | skin (smoothing) | blush | eyeshadow | — |
| `_b` | 2048² | lip SDF `0.5 + d/16` (mm to the canonical border, − inside) | freckles | gloss / highlighter | inner-corner light |

Masks are geometry only, baked by engine `tools/gen_arkit_makeup.py` on the
canonical ARKit head in millimetres and padded past their UV islands for
mipmapping. Topology facts it relies on: the eye-hole rims are the lash
lines (upper rims 1101→1090 and 1069→1080); the 36-vertex loops around the
mouth hole bound the lips — loop 3 is the canonical head's vermilion border
(the SDF's zero), real lips are read from the camera inside it. Colors and
amounts retune live in the JSON without rebaking.

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
