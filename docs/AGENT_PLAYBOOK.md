# Agent playbook — Phases 2–8

*Execution plan for Claude agents carrying the iOS port from here. Written
2026-07-03, immediately after Phase 0/1 closed. Assumes a macOS machine with
Xcode + CMake for most phases; Phase 8 partially runs on Linux.*

---

## Ground rules (read first, they are load-bearing)

1. **Two repos, sibling checkouts.**
   `~/dev/pop-maker-studio` (engine + desktop app, branch `dev`) and
   `~/dev/pms-ios` (this repo). Generators here read the engine repo at
   `$PMS_DESKTOP` (default `~/dev/pop-maker-studio`).
2. **The levers doctrine.** Every UI/product feature goes through
   `engine_command(json)` — the 83 commands in `docs/LEVERS.md`. If a screen
   or test needs something the levers don't expose, that is an ENGINE change
   (add the handler in `src/ipc_server.cpp`, regen manifests with
   `tools/codegen_effects.py` + `tools/gen_agent_tools.py`, then regen
   `docs/LEVERS.md` here). Never bypass into engine internals.
3. **The boundary is compile-enforced.** Engine sources must not include
   `ui/...` or GLFW; `tools/check_engine_deps.sh` (engine repo) fails the
   build otherwise. When you hit it, hoist the symbol properly (pattern:
   every hoist so far is documented in the engine repo's git log —
   `git log --oneline --grep="hoist"`).
4. **Verify, then claim.** Every phase below has an executable "proof"
   step. Run it. A build that compiles is not a feature that works; this
   project verifies renders by diffing pixels and verifies behavior through
   the rig. If you claim parity, attach numbers.
5. **Stale-instance trap.** When live-testing, `pkill -f` can miss
   instances and an old binary will silently serve your test socket —
   verify `readlink /proc/<pid>/exe` (Linux) / `lsof` (macOS) before
   trusting results. This has burned us twice.
6. **Cache versioning rule.** Any change to the face tracker's algorithm
   requires bumping the face-cache version (writer `uint32_t version = 9` in
   `face_track.cpp`, reader gate `version != 9` in `face_cache.cpp`) —
   otherwise stale caches "verify" the old code. Same principle applies to
   any new cache you introduce.
7. **Commits:** detailed messages explaining WHY, no `Co-Authored-By`
   lines. Push `pms-ios` to `origin/main`, engine to `origin/dev`.

## Current state (what you inherit)

- **Engine**: `pms-engine` static lib links standalone (zero app symbols;
  whole-archive link test). C ABI in `src/pms_engine.{h,cpp}` (engine repo)
  = `Engine/include/pms_engine.h` (here; keep in sync — see Phase 2.4).
  `engine_tick` heartbeat + typed event feed (playhead / pipeline /
  loudness / face_track / takes) already drive `pms_tick`/`pms_poll_events`.
- **Proof binary**: `engine-smoke` (engine repo `tools/engine_smoke.cpp`) —
  drives levers headless, exits 0. Build target exists; treat it as the
  boundary CI gate.
- **Shaders**: all 108 registry effects transpile GLSL→SPIR-V→MSL
  (`tools/transpile_shaders.py`; outputs + std140 param ABI in
  `Shaders/msl/params_manifest.json`).
- **Swift scaffold**: `App/Sources/` — EngineBridge (ABI chokepoint +
  event pump), RenderView (MTKView), CameraCapture (AVFoundation),
  VisionMatte (person segmentation), placeholder ContentView. XcodeGen
  `project.yml` builds with the engine framework optional-linked.
- **NOT done**: any Apple-platform build of the engine; pms_render; the
  MediaBackend/CaptureBackend/RenderSurface seams are *documented shapes*,
  not code.

---

## Phase 2 — Engine builds on Apple platforms (`pms_engine.xcframework`)

**Goal:** the standalone lib compiles for macOS (first) and iOS + simulator,
packaged as an xcframework this repo links.

> **STATUS 2026-07-03: P2.1 + P2.2 DONE — engine builds and passes on macOS.**
> `pms-engine` + `engine-smoke` build with Apple clang/libc++ against the
> iOS-26 SDK toolchain and PASS headless (add_track/add_clip/save_project/
> get_project) on an **Intel** 2020 MacBook (Sequoia 15.7, Xcode 26.3).
> Reproducible via `scripts/build_mac.sh --run` in the engine repo (needs
> `brew install pkg-config ffmpeg fftw aubio freetype jpeg-turbo onnxruntime
> whisper-cpp`). PMS_ENGINE_ONLY skips the desktop app + GLFW/vterm/PipeWire.
>
> Portability fixes it took (all in engine `dev`, one commit each — useful
> reference for the iOS slice, which hits the same libc++/BSD surface):
> BSD mktemp (no suffix after Xs); explicit `signal.h`/`unistd.h` (kill/
> mkdtemp were transitively included via now-gated linux headers);
> `std::complex<float>` instead of `vector<fftwf_complex>` (libc++ rejects
> vector-of-C-array); `linux/videodev2.h` + V4L2 enum gated `__linux__`
> (empty device list until the AVFoundation CaptureBackend); `gl_compat.h`
> (Apple ships OpenGL 4.1 core — desktop GL renderer compiles as-is, no stub
> needed for macOS; iOS still gets Metal); Homebrew keg paths — ORT header
> nesting (include/onnxruntime/), fftw pkg-config include, `link_directories`
> for keg `-L`, and ORT link-dir must be **PUBLIC** so static-lib consumers
> inherit it (Linux masked all keg-path bugs — libs sit in /usr/lib). audio_
> pw.cpp (PipeWire) excluded on Apple; engine-consumed embedded assets
> (portrait/fx_motion/fx_face/inter_font) now depend from pms-engine directly.
>
> **P2.3 + P2.5 DONE 2026-07-03 — the app BUILDS against the real engine
> for the iPhone (arm64 device).** `PopMakerStudio.app` (arm64, ~35 MB,
> engine statically embedded — pms_command/pms_create present, no dylib
> deps) links: libpms-engine.a (PMS_HEADLESS iOS build) + whisper/ggml
> (merged) + onnxruntime.xcframework + Accelerate/Metal/MetalKit/AVFoundation/
> AudioToolbox/CoreAudio/CoreML + libc++, with the real EngineBridge (no
> ENGINE_MOCK) via a Swift bridging header. Reproducible: engine
> `scripts/build_xcframework.sh` → pms-ios `xcodegen generate` + `xcodebuild
> -sdk iphoneos26.2`. The iOS gating (PMS_HEADLESS + the ~15 iOS-arch fixes)
> is all in engine `dev`.
>
> iOS-arch fixes beyond the macOS set: system()→pms_system shim (no spawn),
> gl_compat.h iOS-empty + GL handle typedefs, audio.cpp as Objective-C++
> (miniaudio CoreAudio backend), Apple audio frameworks, face_filters GL
> gating, pms_render/capture/model_status ABI stubs, -lc++.
>
> REMAINING to run on-device (needs the physical device + free Apple ID):
> code signing. Open pms-ios/PopMakerStudio.xcodeproj in Xcode → add the
> Apple ID (Settings→Accounts) → target Signing: automatic, Personal Team →
> install the iOS 26.2 device platform component (Settings→Components) →
> plug in + trust the iPhone → Run.
>
> **PROVEN ON-DEVICE 2026-07-03:** the app runs on Alexis's iPhone
> (iOS 26.5) — RenderView (9:16, black: the pms_render Metal stub) +
> transport reading a live playhead from pms_command(get_project). The
> C++ engine is alive on iOS. P2 COMPLETE; the black canvas is the
> Phase 3 (Metal RenderSurface) entry point.

2.1 **macOS build first.** In the engine repo, drive the existing CMake with
    the Xcode/clang toolchain. Expected friction, in order:
    - `GL_GLEXT_PROTOTYPES` / `<GL/gl.h>`: macOS headers differ
      (`<OpenGL/gl3.h>`), and GL is unavailable on iOS entirely. Do NOT
      chase GL portability — instead gate all GL-using engine sources
      (`fx_shader.cpp`, `render.cpp`, GL parts of `face_filters.cpp`,
      `body_fx.cpp`, `overlay_renderer.cpp` backend calls) behind a
      `PMS_RENDERER_GL` compile flag and provide a stub
      `PMS_RENDERER_NONE` build that compiles them out. The lib must first
      build *headless* (timeline/serializer/audio/ML only) — that subset
      is what `engine-smoke` needs, and it's the Phase 3 baseline.
    - ffmpeg child processes: fine on macOS (fork allowed) — desktop
      MediaBackend works as-is there. iOS needs Phase 4 first; for the
      iOS lib, stub the media calls behind the same flag pattern
      (`PMS_MEDIA_FFPROC` / `PMS_MEDIA_STUB`).
    - `audio_pw.cpp` (PipeWire) is Linux-only: exclude on Apple;
      miniaudio's CoreAudio backend covers it.
    - V4L2 in `video_recorder.cpp` capture: gate `PMS_CAPTURE_V4L2`.
2.2 **Proof:** `engine-smoke` builds and PASSES on macOS with the headless
    renderer/media stubs. This is the gate for everything else.
2.3 **iOS slice → xcframework.** Detailed & grounded 2026-07-03 (whisper
    scout + empirical link check on the Intel Mac). Execution order:

    **(a) Establish the gating flags — DO THIS FIRST, it's the real blocker.**
    Empirical fact: `nm -u build-mac/engine-smoke` shows the core path
    references `avcodec_*`, `swscale`, `FT_*`, and OpenGL symbols — so for iOS
    the media + GL code must be STUBBED AT SOURCE (function bodies compiled
    out), NOT merely library-omitted. Two flags, defaulting to the current
    desktop behavior:
      - `PMS_MEDIA_STUB` (iOS): the ~27 media-surface files' ffmpeg/popen
        entry points return empty/error. Real AVFoundation impl = Phase 4.
        Wholesale-exclude the pure-media TUs (proxy, conform, scene_detect,
        blender_export, separate, beat_detect audio decode, video,
        video_recorder, vc_*, waveform, av_measure, bg_remove, noise_reduce);
        per-function-stub the ones with core logic + incidental media calls
        (audio, transcribe audio-decode, hf_api, pipeline_core, render export).
      - `PMS_RENDERER_NONE` (iOS): the 7 GL files stub their public surface
        (fx_apply/scene_*/face_beauty_apply/face_makeup_apply/render_tick_gl/
        runtime_fx_poll) to no-ops returning 0. Real Metal = Phase 3. NOTE
        `engine_tick(gl_ready=false)` already avoids GL calls — verify no
        core path (add_clip/save/get_project) hits a stubbed symbol at RUN
        time. Wholesale-gate fx_shader, body_fx; stub the GL portions of
        face_filters, render, video, runtime_fx behind the flag.
      Verify on Linux/macOS that BOTH flags OFF = unchanged (current builds),
      and a macOS build with both flags ON still links engine-smoke and
      passes — that proves the stubs are self-consistent BEFORE touching iOS.

    **(b) iOS-arch dependencies.**
      - whisper.cpp + ggml: **VALIDATED 2026-07-03 on the Intel Mac** —
        cross-built clean for ios-arm64 (ggml-org/whisper.cpp @6fc7c33) with
        `cmake -G Ninja -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos
        -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0
        -DBUILD_SHARED_LIBS=OFF -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON
        -DGGML_OPENMP=OFF -DWHISPER_BUILD_{EXAMPLES,TESTS,SERVER}=OFF`.
        Produced arm64 libwhisper.a + libggml{,-base,-cpu,-metal,-blas}.a;
        `nm libggml-metal.a | grep metallib` = 4 symbols (Metal embedded, no
        bundle). Ninja works for iOS (no Xcode generator needed). Vendor
        whisper.cpp >=1.7.x (submodule); cross-
        build STATIC per slice with the leetal/ios-cmake toolchain (keeps
        Ninja): `-DPLATFORM=OS64` (device arm64). Flags (all REQUIRED):
        `-DBUILD_SHARED_LIBS=OFF -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON
        -DGGML_OPENMP=OFF -DWHISPER_BUILD_{EXAMPLES,TESTS,SERVER}=OFF
        -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0`. EMBED_LIBRARY=ON is mandatory —
        it bakes the Metal shaders into the .a (ggml_metallib_start/_end) so
        no default.metallib bundle is needed. `cmake --install` to a per-slice
        prefix → yields lib/cmake/whisper + lib/cmake/ggml configs; then reuse
        our EXISTING `find_package(whisper CONFIG)` line unchanged, just point
        `-Dwhisper_DIR` at the iOS prefix. Link set: libwhisper + libggml-base
        + libggml + libggml-cpu + libggml-metal + libggml-blas.
      - ONNX Runtime: use the OFFICIAL prebuilt iOS package (do NOT build
        from source). CONFIRMED 2026-07-03: ORT does NOT ship iOS assets on
        its GitHub releases (latest v1.27.0 has none) — iOS comes via the
        `onnxruntime-c` (C/C++) CocoaPod, which vends an onnxruntime.xcframework.
        So the pms-ios app pulls ORT via CocoaPods/SPM and the engine's iOS
        CMake build points -DONNXRUNTIME_ROOT at the pod's extracted
        xcframework ios-arm64 slice (headers + libonnxruntime.a). arm64 device slice is what matters. CoreML EP is
        available via `AppendExecutionProvider("CoreML", ...)` — defer wiring
        to Phase 6; CPU EP links fine. Point our `-DONNXRUNTIME_ROOT` at the
        xcframework's ios-arm64 slice (headers + libonnxruntime.a).
      - ffmpeg: NO iOS build exists and none is wanted — `PMS_MEDIA_STUB`
        removes all libav references (that's why (a) is the gate).
      - fftw/aubio: fftw builds trivially for iOS (`--host=arm-apple-darwin`
        or the cmake toolchain); aubio only used by beat_detect which is a
        media-stub TU — likely excluded on iOS, confirm.

    **(c) CMake iOS build + xcframework.** `tools/build_xcframework.sh`:
      configure a device slice — `cmake -B build-ios -G Ninja
      -DCMAKE_TOOLCHAIN_FILE=ios.toolchain.cmake -DPLATFORM=OS64
      -DPMS_ENGINE_ONLY=ON -DPMS_MEDIA_STUB=ON -DPMS_RENDERER_NONE=ON
      -DONNXRUNTIME_ROOT=<ios-arm64> -Dwhisper_DIR=<ios prefix>` → build
      libpms-engine.a → `xcodebuild -create-xcframework -library
      build-ios/libpms-engine.a -headers src/pms_engine.h -output
      Engine/build/pms_engine.xcframework`.

    **(d) INTEL-MAC REALITY (this machine).** The host is an Intel Mac, so
    its simulator is x86_64. Recent ORT iOS packages often ship ONLY arm64
    simulator slices → the x86_64 simulator path is likely dead on THIS
    machine. Do NOT block on the simulator: build the **arm64 device slice**
    and prove P2.3 on Alexis's real iPhone (iOS 26.5) via Xcode. The device
    slice is a normal arm64-from-x86_64 cross-compile — the Intel host is
    fine for BUILDING it, just not for running the sim.

    **(e) Proof for P2.3.** engine-smoke is a CLI (can't run on-device without
    an app wrapper). Prove the device slice by: (1) the .a links clean for
    ios-arm64 with all deps resolved (`ld -r` dry link or a trivial
    ios-arm64 test exe); (2) the xcframework validates
    (`xcodebuild -create-xcframework` succeeds, no arch collision); (3) the
    pms-ios app links it (step 2.5 below) and `pms_command("get_project")`
    returns JSON in the running app on-device. That on-device JSON round-trip
    IS the P2.3 proof.
4.  **Header sync:** replace the hand-copied `Engine/include/pms_engine.h`
    with the engine repo's `src/pms_engine.h` at build time (the script
    copies it; a CI check diffs them). One source of truth: the engine repo.
5.  **Proof:** the Xcode project here builds and runs in the simulator,
    `EngineBridge.start()` succeeds, `pms_command("get_project")` returns
    JSON, events pump. Screenshot the placeholder ContentView with a live
    playhead readout.

**Gotcha inventory:** ONNX Runtime needs the official iOS package (CocoaPods
`onnxruntime-c` or the prebuilt xcframework) — do NOT try to cross-compile
ORT yourself. whisper.cpp compiles fine for iOS (Metal backend flag). Defer
both: the headless-stub lib links without ML only if you also gate the ML
sources — prefer linking ORT properly from the start (it's low-friction).

## Phase 3 — Metal renderer (RenderSurface seam)

> **STATUS 2026-07-03: RenderSurface FOUNDATION done + verified.**
> src/metal_render.mm implements pms_render on Apple: pms_create captures
> the MTLDevice → command queue + pipeline; pms_render encodes a render
> pass into the app's drawable texture each frame. Verified with an
> offscreen PNG harness (tools/metal_render_test.mm, macOS host — no
> sim/device needed): renders a lavender aurora, correct pixels. Builds
> + links for arm64 device. This is the plumbing everything hangs on.
> NEXT increments (swap into the fragment/compositor, verify via the PNG
> harness each step): (1) procedural backgrounds from the transpiled MSL
> registry (Shaders/msl/ + params_manifest), (2) textured-quad compositor
> = the 'over' operator (backgrounds/video/text all become quads), (3)
> text via imgui_impl_metal (lyric/title clips — real content, no media),
> (4) the generated FX passes, (5) hand passes (beauty/warp/makeup/chroma).

**Goal:** `pms_render(engine, mtl_texture, w, h)` composites a frame with
pixel parity against desktop GL.

3.1 **Seam:** define `RenderBackend` in the engine (create target textures,
    run generated-FX passes, run hand passes, final composite). The GL
    implementation is a refactor of `fx_shader.cpp`'s existing structure
    (it already renders FBO-to-FBO; the seam formalizes texture handles).
    Keep GL working on Linux — it is the parity reference.
3.2 **Generated effects on Metal:** consume `Shaders/msl/` +
    `params_manifest.json`. One compute-less fragment pipeline per effect;
    fill a single uniform buffer per draw using the manifest's std140
    offsets (that manifest IS the ABI — do not hand-declare structs).
    Extend `tools/transpile_shaders.py` if any registry shader gains new
    uniform types (it asserts on unknown types — good, keep it strict).
3.3 **Hand-written passes**, port in this order (dependency + payoff):
    scene compositor (`scene_begin/add_layer/apply_fx/result`) → blit/blend
    helpers → face beauty (`k_face_beauty_fs` — big fragment, transpiles
    with the same tool if you lift its loose uniforms; try tool-first) →
    face warp → UV makeup mesh pass (vertex+fragment, 468 verts/898 tris,
    dynamic VBO — note the CPU-side folded-triangle cull, keep it) → chroma
    feedback family (Melt/Echo/Frame keep per-slot ring state textures) →
    text overlay path (ImGui drawlists via the official
    `imgui_impl_metal` backend).
3.4 **Zero-copy camera:** CVPixelBuffer → CVMetalTextureCache → MTLTexture
    for `pms_submit_camera_frame`. Spike this EARLY (it constrains pixel
    formats: prefer BGRA capture).
3.5 **Proof — golden frames:** build a parity harness: same .pms + same
    seed → render frame t on desktop GL (Linux, existing rig) and on Metal
    (macOS) → per-pixel diff. Gate: mean abs diff < 1.0/255 per effect for
    all 108 registry effects + each hand pass. Ship the harness as
    `tools/golden_parity.py` here; it is the Phase 3 exit criterion.

**Known trap:** FBO save-order — the GL code had a bug class where
framebuffer state was captured AFTER creating a new target ("one black
frame"). In Metal this class disappears (explicit encoders), but the
equivalent trap is forgetting to end an encoder before reading its target.

## Phase 4 — MediaBackend: AVFoundation/VideoToolbox

**Goal:** decode/probe/export/takes with no child processes.

4.1 Define `MediaBackend` (engine header): `probe(path) → {fps_num/den, w,
    h, duration, audio}`, `open_decode(path) → session`, `decode_at(session,
    t) → CVPixelBuffer/texture`, `open_encode(path, params) → sink`,
    `write_video/write_audio/finish`. Wrap today's ffmpeg-child code as
    `MediaBackendFFProc` (Linux/macOS) — behavior must not change on
    desktop; the rig is your regression net.
4.2 `MediaBackendAV` (Apple): `AVAssetReader`+VideoToolbox decode,
    `AVAssetWriter` (H.264/HEVC) encode, `AVAudioFile` for audio decode.
    **fps must come from the original asset** (the proxy-fps trap is
    documented history — never probe a derived file for timing).
4.3 Proxies: on iOS, skip MJPEG proxies initially (hardware decode is fast);
    keep the seam able to reintroduce them if scrubbing profiling demands.
4.4 Takes: camera frames → per-take `AVAssetWriter`, same loop-clock
    slicing logic (that logic is engine code — `video_recorder.cpp` — only
    the sink is per-platform; the session-stamp identity fix must survive).
4.5 **Proof:** on macOS with `MediaBackendAV` forced: load
    `no_glasses_test.pms` equivalent media, scrub-decode 20 random times,
    export 3 seconds; compare export against the ffproc backend's output
    (PSNR > 40 dB, duration exact, A/V offset < 10 ms — reuse the
    `av_measure` tooling in the engine).

## Phase 5 — Capture + record loop on device

**Goal:** live mirror with face filters + loop-recorded takes on iPhone.

5.1 Wire `CameraCapture.swift` → `pms_submit_camera_frame` (finish the
    stubbed delegate): BGRA CVPixelBuffers, quarter-turn rotation from
    device orientation (the engine's roll ladder tolerates the rest), host
    time for the loop clock. Mic blocks → `pms_submit_mic_block`.
5.2 Engine intake: implement the submit functions (half-res tracker feed —
    port the intake path from `ui/canvas.cpp`'s mirror block, which is the
    reference implementation, into the engine behind the CaptureBackend
    seam; the desktop keeps its path until parity, then converges).
5.3 The live-mirror composite moves fully engine-side (it is mostly there:
    `face_filter_apply_obs` chain) so `pms_render` shows the filtered
    mirror with zero Swift-side pixel work.
5.4 **Proof:** on-device (or simulator+fake cam): mirror at 30+ fps with
    Douyin filter on an A15-class device; record a 3-cycle loop; takes
    appear via the `takes` event; playback shows the filtered take
    (the take path live-tracks when the cache is stale — verify by
    deleting the face cache and confirming filters still render).
    Instrument with signposts; attach the fps numbers.

## Phase 6 — ML on device

6.1 ORT + CoreML execution provider; per-model validation order: face trio
    (YuNet/landmarks/blendshapes — bundle these, ~5 MB), Kim_Vocal_2,
    wav2vec2 CTC, whisper.cpp-Metal (tier by device: large-v3-turbo only
    on ≥8 GB devices, else small/tiny — add a device-tier table).
6.2 Model packs: reuse `hf_api.cpp` download plumbing against the existing
    HF repo (`verticalrectangle/pop-maker-studio-models`); packs land in
    `state_root/models`; expose via `pms_model_status` + a
    `download_model_pack` lever (new engine handler + manifest regen).
6.3 Background removal: wire `VisionMatte.swift` output into the engine's
    bg-remove seam (single-channel matte texture, same shape RVM produces).
    RVM stays desktop-only (GPL — the compliance decision is final).
6.4 Deferred to post-v1 (do not build): Moondream, RVC voice convert,
    Piper TTS.
6.5 **Proof:** face trio latency < 8 ms/frame on device (half-res input);
    a 30 s song transcribes + aligns end-to-end on device; vocal
    separation completes (any speed) without memory pressure kills —
    profile with Instruments allocations.

> **STATUS 2026-07-03: the Glass SwiftUI shell is INTEGRATED, builds both ways.**
> Alexis's design workflow produced a 14-file app (glass UI, lavender accent,
> levers-correct via EditorModel -> command()). In App/Sources: simulator
> (ENGINE_MOCK) build runs (Home live); device (real engine) build links. Its
> EngineBridge was my exact bridge (identical). Not-yet-ported (design's note):
> drag-to-timeline, keyframes, multicam, loop region, transcript search.

## Phase 7 — Screens (the design workflow's lane)

Owned by Alexis's Claude design workflow; engineering agents support:
- Keep `docs/LEVERS.md` regenerated on every engine manifest change.
- Add levers the screens request via the doctrine (rule 2). Known gaps to
  expect: project browser needs `list_projects` (recents exist via
  `recent_projects_list` — expose as a lever), thumbnails need a
  `get_project_thumb` lever, undo/redo already exist.
- Screen order that matches engine readiness: Home/projects (after P2) →
  Timeline read-only + transport (P2) → Export (P4) → Record + filters
  (P5) → full editing (P4+, incremental).
- Rule for every screen PR: state which levers it consumes; no direct
  engine includes in Swift beyond `pms_engine.h`.

## Phase 8 — Test rig + CI across platforms

8.1 **Linux CI (exists informally — formalize):** build + boundary check +
    `engine-smoke` + the headless rig smoke (open test project, filter,
    render snapshot, numeric diff).
8.2 **macOS CI:** engine lib (headless stub) + `engine-smoke`; once P3
    lands, the golden-frame parity harness (3.5) joins the gate.
8.3 Port the fake-cam fixture: `PMS_FAKE_CAM` becomes a CaptureBackend
    implementation (not an env hack) so the same face-filter tests run on
    all platforms and in the simulator.
8.4 The agent-driven rig (socket IPC) works wherever the desktop app runs;
    on iOS the equivalent is `engine_command` in-process — add a tiny
    `EngineTestHost` macOS target here that exposes the same socket
    protocol over the xcframework, so existing rig scripts run unchanged
    against the Apple build. This is the highest-leverage piece of Phase 8:
    it makes every existing verification script cross-platform.

---

## Dependency graph & suggested agent assignment

```
P2 (xcframework) ──► P3 (Metal) ──► P5 (capture/mirror) ──► P6 (ML)
      │                                    ▲
      └──► P4 (media) ─────────────────────┘
P7 (screens) starts after P2, continues throughout
P8.1 (Linux CI) anytime; P8.2+ after P2; P8.4 after P2
```

Parallelizable as three lanes: (A) P2→P3 renderer lane, (B) P4 media lane,
(C) P7 screens + P8 rig lane. P5 is the convergence point — schedule it
when A and B both land.

## Definition of done, per phase

Every phase closes with: proof step green + numbers attached, desktop rig
still green (no regression on Linux), boundary check green, docs updated
(this file's phase section gets a STATUS block like the engine repo's plan),
commits pushed. If a phase uncovers work belonging to another lane, write it
into that phase's section here rather than doing it inline.
