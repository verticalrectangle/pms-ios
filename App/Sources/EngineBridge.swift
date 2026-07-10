// EngineBridge.swift — the ONLY file that touches the C ABI (pms_engine.h).
// Swift-side rules mirror the engine contract:
//   - screens call `result(_:_:)` with lever JSON, never engine internals;
//   - a top-level `error` in the reply is a FAILED mutation → thrown, published;
//   - state flows one way: pollEvents() -> published properties.
// Threading: pms_command is main-thread only. Export calls render/renderWait/
// submitCameraFrame from its worker queue ONLY while ticks + preview are paused
// (exclusive engine access), matching the desktop contract.
import Foundation
import Metal
import Combine
import QuartzCore   // CADisplayLink
import CoreVideo    // CVPixelBuffer (camera/decoded frames)

// ENGINE_MOCK (set in project.yml for simulator builds): screens develop against
// MockEngine — same command contract, same rejection behavior, no C ABI.
#if ENGINE_MOCK
typealias PMSEngineHandle = MockEngine
#else
typealias PMSEngineHandle = OpaquePointer
#endif

enum EngineError: LocalizedError {
    case notStarted
    case encode(String)
    case nullReply
    case rejected(String)
    case malformedReply

    var errorDescription: String? {
        switch self {
        case .notStarted:          return "Engine not started"
        case .encode(let d):       return "Could not encode command: \(d)"
        case .nullReply:           return "Engine returned no reply"
        case .rejected(let e):     return e
        case .malformedReply:      return "Engine reply was not valid JSON"
        }
    }
}

final class EngineStore: ObservableObject {
    private var engine: PMSEngineHandle?
    private var displayLink: CADisplayLink?
    let device: MTLDevice = MTLCreateSystemDefaultDevice()!

    struct PipelineState: Equatable {
        var stage = "idle"
        var progress = 0.0
        var message = ""
    }

    // Published engine state, fed exclusively by the event pump.
    @Published var playhead: Double = 0
    @Published var playing: Bool = false
    @Published var pipeline = PipelineState()
    @Published var takeCount = 0
    @Published var masterLufs: (momentary: Double, integrated: Double)? = nil
    @Published var faceTracking: Bool = false
    @Published var busy: (label: String, progress: Double)? = nil
    @Published var lastError: String? = nil

    /// False when pms_create/ABI validation failed — screens show a hard error.
    @Published private(set) var healthy = false

    func start() {
        guard engine == nil else { return }
#if ENGINE_MOCK
        engine = MockEngine()
        healthy = true
#else
        let assets = Bundle.main.resourcePath! + "/EngineAssets"
        let state = FileManager.default.urls(for: .applicationSupportDirectory,
                                             in: .userDomainMask)[0].path
        engine = pms_create(Unmanaged.passUnretained(device).toOpaque(),
                            assets, state)
        // Lifecycle validation: wrong ABI or an unusable engine must fail loudly
        // at startup, not as a cascade of mysterious command errors later.
        guard engine != nil else {
            lastError = "pms_create failed"; healthy = false; return
        }
        guard pms_abi_version() == UInt32(PMS_ENGINE_ABI) else {
            lastError = "Engine ABI mismatch: framework \(pms_abi_version()) vs header \(PMS_ENGINE_ABI)"
            healthy = false
            stop()
            return
        }
        NSLog("[engine] ABI \(pms_abi_version()), .pms v\(pms_project_version())")
        do {
            _ = try result("get_project")
            healthy = true
        } catch {
            lastError = "Engine rejected get_project at startup: \(error.localizedDescription)"
            healthy = false
            stop()
            return
        }
#endif
        let link = CADisplayLink(target: self, selector: #selector(frame))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Tear down the tick + the engine. Safe to call twice.
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
#if !ENGINE_MOCK
        if let e = engine { pms_destroy(e) }
#endif
        engine = nil
    }

    deinit {
        displayLink?.invalidate()
#if !ENGINE_MOCK
        if let e = engine { pms_destroy(e) }
#endif
    }

    @objc private func frame(_ link: CADisplayLink) {
        guard let e = engine else { return }
#if ENGINE_MOCK
        e.tick(link.targetTimestamp - link.timestamp)
        if playing != e.playheadIsAdvancing { playing = e.playheadIsAdvancing }
        if playing { playhead += link.targetTimestamp - link.timestamp }
#else
        pms_tick(e, link.targetTimestamp - link.timestamp)
        pumpEvents(e)
#endif
        // Rendering happens in MetalRenderView's draw, which pulls from here.
    }

    /// Pause the engine tick — offline export takes exclusive engine access (with the
    /// canvas MTKView paused + frame-push suspended, no one else touches the engine).
    func setTicksPaused(_ paused: Bool) { displayLink?.isPaused = paused }

    // MARK: - Commands

    /// The single lever chokepoint. Returns the reply's `result` payload
    /// (object or array); throws EngineError on any failure, publishing it to
    /// `lastError` so screens can surface a banner without extra plumbing.
    @discardableResult
    func result(_ method: String, _ params: [String: Any] = [:]) throws -> Any {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let e = engine else { throw report(.notStarted) }
#if ENGINE_MOCK
        let obj = e.command(method, params)
#else
        let req: [String: Any] = ["id": "ui", "method": method, "params": params]
        guard JSONSerialization.isValidJSONObject(req),
              let data = try? JSONSerialization.data(withJSONObject: req),
              let reqStr = String(data: data, encoding: .utf8) else {
            throw report(.encode(method))
        }
        guard let raw = pms_command(e, reqStr) else { throw report(.nullReply) }
        defer { pms_free(raw) }
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(String(cString: raw).utf8)))
            as? [String: Any] else { throw report(.malformedReply) }
#endif
        if let err = obj["error"] as? String { throw report(.rejected(err)) }
        return obj["result"] ?? [String: Any]()
    }

    /// `result(...)` for callers that expect an object payload.
    @discardableResult
    func resultObject(_ method: String, _ params: [String: Any] = [:]) throws -> [String: Any] {
        (try result(method, params)) as? [String: Any] ?? [:]
    }

    /// Fire-and-forget lever: failure lands in `lastError` only.
    func send(_ method: String, _ params: [String: Any] = [:]) {
        _ = try? result(method, params)
    }

    private func report(_ e: EngineError) -> EngineError {
        lastError = e.errorDescription
        return e
    }

    /// Pass a full JSON envelope {id,method,params} straight to the engine and
    /// return the raw JSON reply — the IPC/agent server's chokepoint. Call on main.
    func rawCommand(_ json: String) -> String {
        guard let e = engine else { return #"{"error":"engine not started"}"# }
#if ENGINE_MOCK
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
              let method = obj["method"] as? String else { return #"{"error":"bad request"}"# }
        let reply = e.command(method, obj["params"] as? [String: Any] ?? [:])
        let data = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
#else
        guard let raw = pms_command(e, json) else { return #"{"error":"null reply"}"# }
        defer { pms_free(raw) }
        return String(cString: raw)
#endif
    }

    // MARK: - Render / frame submission

    func render(into texture: MTLTexture) {
        guard let e = engine else { return }
#if ENGINE_MOCK
        _ = e   // MetalRenderView clears; the engine composite arrives with P3
#else
        let rc = pms_render(e, Unmanaged.passUnretained(texture).toOpaque(),
                            Int32(texture.width), Int32(texture.height))
        if rc != 0 && lastRenderRC == 0 {   // report once per failure streak
            DispatchQueue.main.async { self.lastError = "Renderer error (pms_render rc=\(rc))" }
        }
        lastRenderRC = rc
#endif
    }
    private var lastRenderRC: Int32 = 0

    /// Block until the GPU finishes the committed render — offline export readback.
    func renderWait() {
        guard let e = engine else { return }
#if !ENGINE_MOCK
        pms_render_wait(e)
#else
        _ = e
#endif
    }

    /// Push a captured/decoded frame (CVPixelBuffer, 32BGRA) to the engine — it
    /// composites it into the canvas via pms_render. Called off the camera queue.
    func submitCameraFrame(_ pixelBuffer: CVPixelBuffer, rotation: Int32, hostTime: Double) {
        guard let e = engine else { return }
#if ENGINE_MOCK
        _ = e
#else
        pms_submit_camera_frame(e, Unmanaged.passUnretained(pixelBuffer).toOpaque(),
                                rotation, hostTime)
#endif
    }

    /// Push a mic block (interleaved stereo Float32) into the engine's capture
    /// injection ring. Called from the audio capture queue — the ring is SPSC.
    func submitMicBlock(_ interleavedLR: UnsafePointer<Float>, frames: Int, sampleRate: Double) {
        guard let e = engine, frames > 0 else { return }
#if ENGINE_MOCK
        _ = e
#else
        pms_submit_mic_block(e, interleavedLR, frames, sampleRate)
#endif
    }

    /// Submit one visual layer's frame, addressed by engine (track, clip) —
    /// the scene compositor stacks layers in track order (bottom lane deepest).
    /// nil clears the layer. The engine retains until superseded, so static
    /// layers (text rasters) can be submitted once.
    func submitLayerFrame(track: Int, clip: Int, _ pixelBuffer: CVPixelBuffer?,
                          rotation: Int32 = 0, hostTime: Double) {
        guard let e = engine else { return }
#if ENGINE_MOCK
        _ = e
#else
        pms_submit_layer_frame(e, Int32(track), Int32(clip),
                               pixelBuffer.map { Unmanaged.passUnretained($0).toOpaque() },
                               rotation, hostTime)
#endif
    }

    /// Submit a Vision person matte (OneComponent8 CVPixelBuffer; nil clears).
    /// The engine retains the buffer. Called off the Vision worker queue.
    func submitPersonMatte(_ matte: CVPixelBuffer?, hostTime: Double) {
        guard let e = engine else { return }
#if ENGINE_MOCK
        _ = e
#else
        pms_submit_person_matte(e, matte.map { Unmanaged.passUnretained($0).toOpaque() },
                                hostTime)
#endif
    }

    /// Clear the composited content frame back to the empty (aurora) canvas.
    func clearContent() {
        guard let e = engine else { return }
#if ENGINE_MOCK
        _ = e
#else
        pms_submit_camera_frame(e, nil, 0, 0)   // null buffer → compositor clears
#endif
    }

    // MARK: - Events

#if !ENGINE_MOCK
    private func pumpEvents(_ e: PMSEngineHandle) {
        guard let raw = pms_poll_events(e) else { return }
        defer { pms_free(raw) }
        guard let events = (try? JSONSerialization.jsonObject(
            with: Data(String(cString: raw).utf8))) as? [[String: Any]] else { return }
        for ev in events {
            switch ev["type"] as? String {
            case "playhead":
                playhead = ev["t"] as? Double ?? playhead
                playing = ev["playing"] as? Bool ?? playing
            case "pipeline":
                let p = PipelineState(stage: ev["stage"] as? String ?? "idle",
                                      progress: ev["progress"] as? Double ?? 0,
                                      message: ev["message"] as? String ?? "")
                pipeline = p
                busy = (p.stage == "idle" || p.stage == "done" || p.stage == "error")
                    ? nil : (p.message.isEmpty ? p.stage : p.message, p.progress)
                if p.stage == "error", !p.message.isEmpty { lastError = p.message }
            case "loudness":
                if let m = ev["momentary"] as? Double,
                   let i = ev["integrated"] as? Double { masterLufs = (m, i) }
            case "face_track":
                faceTracking = ev["valid"] as? Bool ?? false
            case "takes":
                takeCount = ev["count"] as? Int ?? takeCount
            case "busy":
                if let label = ev["label"] as? String,
                   let p = ev["progress"] as? Double { busy = (label, p) }
                else { busy = nil }
            case "error":
                lastError = ev["message"] as? String
            default: break
            }
        }
    }
#endif
}
