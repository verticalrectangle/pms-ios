# Pop Maker Studio — SwiftUI shell

Pure SwiftUI port of the glass UI, wired to your `EngineStore` (EngineBridge.swift).
The design language is preserved — white-on-black, hairline depth, glass material —
with the accent switched from amber to **lavender** (`#B5A8FF`, `Theme.accent`).

## Architecture

State flows exactly as your bridge dictates: **one way in** (published properties
off `EngineStore`, fed by `pollEvents()`), **levers out** (`command(_:_:)`).

```
EngineStore (yours)         ← engine truth: playhead, playing, masterLufs, busy, lastError
   ▲ command(_:_:)          ← every mutation goes through here as a lever
   │
EditorModel                 ← editable scene projection; mutates optimistically + sends levers
   │
SwiftUI screens             ← render published state, never touch engine internals
```

No screen constructs lever JSON by hand beyond `command(method, params)`; the engine
stays the single source of truth. `EditorModel` mirrors the scene so the UI can render
and edit at 60fps, then reconciles through levers.

## Files

| File | Role |
|---|---|
| `PopMakerApp.swift` | `@main`, root home↔editor nav, single `EngineStore` |
| `Theme.swift` | tokens, lavender accent, `.glass()` material, atmosphere |
| `Models.swift` | value types + a real slice of the 109-effect registry, body/audio FX, AI actions, sample scene |
| `EngineBridge.swift` | **your** engine bridge (copied in so the package compiles) |
| `EngineStore+Prototype.swift` | dev-only `simulateBusy` / mock meters (inert with the real engine) |
| `EditorModel.swift` | scene projection + every lever call |
| `MetalPreview.swift` | `MTKView` hosting; hands the drawable texture to `render(into:)` |
| `HomeView.swift` | project library |
| `EditorView.swift` | canvas + transport + timeline + dock + inspector + fullscreen player |
| `TimelineView.swift` | tracks, four brick flavours, beat grid, chapters, playhead |
| `TransportBar.swift` | transport, BPM, LUFS meter, tool dock, busy bar |
| `FXSheet.swift` | effect browser (Video / Body / Audio tabs) |
| `InspectorView.swift` | brick param sliders + Multi-FX chain |
| `Sheets.swift` | Agent (AI actions + chat), Media, Lyrics, Export |

## Brick model (matches the engine)

- **Glass FX** — `add_effect_brick` on a video track → clip-only, pre-composite.
- **Global FX** — `add_effect_brick` on the FX rail → everything below, post-composite.
- **Multi-FX** — `add_multifx_brick`, an ordered chain in one brick (weld to build).
- **Body FX** — `add_body_fx_brick` / `remove_background` (RVM), needs `process_body_fx_masks`.
- **Audio FX** — `add_audio_multifx_brick`, a LIVE chain that auto-welds to the clip.
- Tuning params → `set_clip_fx`. Unwelding → `decouple_fx_brick`.

## On-device AI actions (Agent sheet)

Each tile is one lever + the local model it runs: `describe_video` (Moondream2),
`find_video_moment`, `remove_background` (RobustVideoMatting), `remove_silence`,
`cut_filler_words`, `analyze_audio`, `crop_media`, `generate_chapters`. They drive
the global busy bar via the `busy` event.

## Build

1. New iOS app (iOS 17+), SwiftUI lifecycle. Drop this folder's files into the target.
2. Add **`ENGINE_MOCK`** to *Build Settings → Active Compilation Conditions* until
   `pms_engine.xcframework` exists — screens run against your stub with canned replies.
3. Fonts: the design uses the system font as a stand-in for Inter; add InterVariable +
   VT323 and swap `Font.disp/label` if you want exact brand type.
4. Clear `ENGINE_MOCK` and link the xcframework to run against the real C ABI — no
   screen changes required.

## Not yet ported (say the word)

Drag-to-timeline placement (currently tap-to-place with a Glass/Global toggle),
keyframe editing (`set_clip_keyframes`), multicam, loop region, and the transcript
search UI. The spine is here; these slot onto it.
