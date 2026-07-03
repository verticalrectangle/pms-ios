# Pop Maker Studio — iOS

The iOS shell for the Pop Maker Studio engine. The engine stays **C++**
(timeline, .pms serializer, 109 generated effects, face/beauty/makeup
pipeline, audio, ML) and is consumed here through one C ABI
(`Engine/include/pms_engine.h`). The UI is **SwiftUI**, built screen-by-
screen by a Claude design workflow against the generated lever contract
(`docs/LEVERS.md` — 83 commands + 109 effects).

## Renderer: Metal, native — decided

Chosen over ANGLE for butter: native frame pacing via CADisplayLink/MTKView,
zero-copy camera frames (CVPixelBuffer → CVMetalTextureCache), no GL-on-Metal
translation layer in the hot path.

The cost of that decision is already paid down: **all 108 registry effect
shaders transpile GLSL → SPIR-V → MSL mechanically**
(`tools/transpile_shaders.py`, outputs + std140 param ABI in `Shaders/msl/`).
GLSL in the desktop registry remains the single source of truth; regeneration
is one command. Only the hand-written passes (scene compositor, face
warp/beauty/makeup mesh, chroma feedback family) are ported by hand, behind
the engine's RenderSurface seam.

## App Store compliance

- Background removal uses Apple Vision person segmentation on iOS
  (`App/Sources/VisionMatte.swift`) — RVM (GPL-3.0) does not ship here.
- No ffmpeg: decode/probe/export/takes go through AVFoundation/VideoToolbox
  inside the engine's MediaBackend seam (hardware paths; no LGPL question).
- Models beyond the ~5 MB face trio are download-on-demand from the existing
  HF models repo.

## Layout

    Engine/include/pms_engine.h   the complete C ABI (contract-first; impl
                                  lands with the desktop repo's engine split)
    App/Sources/                  SwiftUI shell: engine bridge, Metal render
                                  view, AVFoundation capture, Vision matte
    Shaders/msl/                  transpiled MSL + params_manifest.json
                                  (std140 offsets = the uniform ABI)
    docs/LEVERS.md                generated command contract (do not edit)
    docs/PLAN.md                  phased port plan
    docs/AGENT_PLAYBOOK.md        execution plan for agents (Phases 2-8:
                                  tasks, proofs, gotchas, lane assignment)
    tools/                        transpile + levers generators

## Building

Screens can be developed today on macOS: `xcodegen generate`, open, run —
the engine framework is optional-linked and the bridge tolerates its absence
(mock state). The real `pms_engine.xcframework` arrives from the desktop
repo's engine-extraction phase (see docs/PLAN.md, Phases 0–3).

Regenerate artifacts (needs a sibling `~/dev/pop-maker-studio` checkout):

    python3 tools/gen_levers.py
    python3 tools/transpile_shaders.py --out-dir Shaders/msl \
        --manifest Shaders/msl/params_manifest.json \
        ~/dev/pop-maker-studio/shaders/*.glsl
