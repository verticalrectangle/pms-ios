// EngineBridge.swift — the ONLY file that touches the C ABI (pms_engine.h).
// Swift-side rules mirror the engine contract:
//   - screens call `command(_:)` with lever JSON, never engine internals;
//   - state flows one way: pollEvents() -> published properties.
import Foundation
import Metal
import Combine
import QuartzCore   // CADisplayLink
import CoreVideo    // CVPixelBuffer (camera/decoded frames)

// ENGINE_MOCK (set in project.yml until pms_engine.xcframework exists):
// screens develop against a stub engine — same observable surface, canned
// replies. Flipping the flag swaps in the real C ABI with zero screen churn.
#if ENGINE_MOCK
typealias PMSEngineHandle = Int
private func mock_reply(_ req: String) -> String {
    if req.contains("get_project") {
        return #"{"id":"ui","result":{"duration":8.0,"fps":30,"playhead":0.0}}"#
    }
    return #"{"id":"ui","result":{"ok":true,"mock":true}}"#
}
#else
typealias PMSEngineHandle = OpaquePointer
#endif

final class EngineStore: ObservableObject {
    private var engine: PMSEngineHandle?
    private var displayLink: CADisplayLink?
    let device: MTLDevice = MTLCreateSystemDefaultDevice()!

    // Published engine state, fed exclusively by the event pump.
    @Published var projectName: String = ""
    @Published var playhead: Double = 0
    @Published var playing: Bool = false
    @Published var masterLufs: (momentary: Double, integrated: Double)? = nil
    @Published var faceTracking: Bool = false
    @Published var busy: (label: String, progress: Double)? = nil
    @Published var lastError: String? = nil

    func start() {
        guard engine == nil else { return }
#if ENGINE_MOCK
        engine = 1
#else
        let assets = Bundle.main.resourcePath! + "/EngineAssets"
        let state = FileManager.default.urls(for: .applicationSupportDirectory,
                                             in: .userDomainMask)[0].path
        engine = pms_create(Unmanaged.passUnretained(device).toOpaque(),
                            assets, state)
#endif
        let link = CADisplayLink(target: self, selector: #selector(frame))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func frame(_ link: CADisplayLink) {
        guard let e = engine else { return }
#if ENGINE_MOCK
        _ = e
        if playing { playhead += link.targetTimestamp - link.timestamp }
#else
        pms_tick(e, link.targetTimestamp - link.timestamp)
        pumpEvents(e)
#endif
        // Rendering happens in MetalRenderView's draw, which pulls from here.
    }

    /// The single lever chokepoint. Returns the engine's JSON reply.
    @discardableResult
    func command(_ method: String, _ params: [String: Any] = [:]) -> [String: Any] {
        guard let e = engine else { return ["error": "engine not started"] }
        let req: [String: Any] = ["id": "ui", "method": method, "params": params]
        let data = try! JSONSerialization.data(withJSONObject: req)
        let reqStr = String(data: data, encoding: .utf8)!
#if ENGINE_MOCK
        _ = e
        if method == "play"  { playing = true }
        if method == "pause" { playing = false }
        let reply = mock_reply(reqStr)
#else
        guard let raw = pms_command(e, reqStr) else { return ["error": "null reply"] }
        defer { pms_free(raw) }
        let reply = String(cString: raw)
#endif
        let obj = (try? JSONSerialization.jsonObject(with: Data(reply.utf8)))
            as? [String: Any] ?? [:]
        if let err = obj["error"] as? String { lastError = err }
        return obj
    }

    func render(into texture: MTLTexture) {
        guard let e = engine else { return }
#if ENGINE_MOCK
        _ = e   // MetalRenderView clears; the engine composite arrives with P3
#else
        _ = pms_render(e, Unmanaged.passUnretained(texture).toOpaque(),
                       Int32(texture.width), Int32(texture.height))
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

    /// Clear the composited content frame back to the empty (aurora) canvas.
    func clearContent() {
        guard let e = engine else { return }
#if ENGINE_MOCK
        _ = e
#else
        pms_submit_camera_frame(e, nil, 0, 0)   // null buffer → compositor clears
#endif
    }

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
            case "loudness":
                if let m = ev["momentary"] as? Double,
                   let i = ev["integrated"] as? Double { masterLufs = (m, i) }
            case "face_track":
                faceTracking = ev["valid"] as? Bool ?? false
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
