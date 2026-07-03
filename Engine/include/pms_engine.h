// pms_engine.h — the complete C ABI between the Pop Maker Studio engine
// (C++, built from the desktop repo's engine sources) and the iOS shell
// (Swift). This header IS the contract: Swift sees nothing else.
//
// Design rules:
//  - One instance per app. All calls from the main/render thread unless
//    noted. The engine runs its own worker threads internally (tracking,
//    transcription, model downloads) exactly as on desktop.
//  - Commands and events are JSON strings — the same 83-lever surface the
//    desktop UI and Claude agents use (see docs/LEVERS.md). No per-feature
//    C functions; features never leak into this ABI.
//  - Rendering targets a caller-provided Metal texture. The engine owns all
//    intermediate passes (scene compositor, FX, face pipeline).
//
// Status: contract only — the implementation lands with the engine
// extraction (desktop repo Phase 0) + Metal renderer (Phase 2).

#pragma once
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct pms_engine pms_engine;   // opaque

// ── Lifecycle ────────────────────────────────────────────────────────────────

// device:      MTLDevice* (bridged void*). Engine creates its own queue.
// asset_root:  bundle path holding bundled models (face trio, sprites,
//              makeup textures) — see pms_model_status for the rest.
// state_root:  app container dir for projects, takes, caches.
pms_engine* pms_create(void* mtl_device,
                       const char* asset_root,
                       const char* state_root);
void        pms_destroy(pms_engine*);

// Advance clocks, pump worker results into engine state. Call once per
// display-link frame, before pms_render.
void pms_tick(pms_engine*, double dt_seconds);

// Composite the current frame into `target` (MTLTexture*, bridged void*,
// BGRA8). Returns 0 on success. The preview view calls this; export runs
// its own loop internally (trigger_export lever) against AVAssetWriter.
int pms_render(pms_engine*, void* mtl_texture, int width, int height);

// ── Commands & events (the levers) ──────────────────────────────────────────

// Execute one command; returns a malloc'd JSON string (caller frees with
// pms_free). Identical semantics to the desktop IPC surface. Thread: main.
char* pms_command(pms_engine*, const char* json_request);

// Drain pending events as a JSON array (progress ticks, loudness meters,
// face-tracker status, take completed, model download progress, error
// toasts). Returns malloc'd string; caller frees. Empty array when idle.
char* pms_poll_events(pms_engine*);

void pms_free(char*);

// ── Capture intake (AVFoundation feeds these) ───────────────────────────────

// Camera frames: CVPixelBufferRef (bridged void*), any orientation —
// rotation_quarter_turns maps device orientation onto the engine's rot_q
// plumbing (the tracker's roll ladder handles the rest). Zero-copy via
// CVMetalTextureCache internally; the half-res tracker submit is derived
// inside. Thread: capture queue (engine synchronizes).
void pms_submit_camera_frame(pms_engine*, void* cv_pixel_buffer,
                             int rotation_quarter_turns,
                             double host_time_seconds);

// Interleaved stereo float mic block, engine-side loop clock alignment.
// Thread: audio callback (realtime-safe path, no allocation).
void pms_submit_mic_block(pms_engine*, const float* interleaved_lr,
                          size_t frames, double sample_rate);

// ── Model packs ─────────────────────────────────────────────────────────────

// JSON status of every model pack: {id, bytes, state: bundled|absent|
// downloading|ready, progress}. Download via the "download_model_pack"
// lever; files land under state_root/models.
char* pms_model_status(pms_engine*);

// ── Version / compatibility ─────────────────────────────────────────────────

// ABI version — bumped on any signature change here.
#define PMS_ENGINE_ABI 1
uint32_t pms_abi_version(void);
// .pms project version this engine reads/writes (desktop parity).
uint32_t pms_project_version(void);

#ifdef __cplusplus
}
#endif
