// EngineBridge.swift — the ONLY file that touches the C ABI (pms_engine.h).
// Swift-side rules mirror the engine contract:
//   - screens call `command(_:)` with lever JSON, never engine internals;
//   - state flows one way: pollEvents() -> published properties.
import Foundation
import Metal
import Combine

final class EngineStore: ObservableObject {
    private var engine: OpaquePointer?
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
        let assets = Bundle.main.resourcePath! + "/EngineAssets"
        let state = FileManager.default.urls(for: .applicationSupportDirectory,
                                             in: .userDomainMask)[0].path
        engine = pms_create(Unmanaged.passUnretained(device).toOpaque(),
                            assets, state)
        let link = CADisplayLink(target: self, selector: #selector(frame))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func frame(_ link: CADisplayLink) {
        guard let e = engine else { return }
        pms_tick(e, link.targetTimestamp - link.timestamp)
        pumpEvents(e)
        // Rendering happens in MetalRenderView's draw, which pulls from here.
    }

    /// The single lever chokepoint. Returns the engine's JSON reply.
    @discardableResult
    func command(_ method: String, _ params: [String: Any] = [:]) -> [String: Any] {
        guard let e = engine else { return ["error": "engine not started"] }
        let req: [String: Any] = ["id": "ui", "method": method, "params": params]
        let data = try! JSONSerialization.data(withJSONObject: req)
        guard let raw = pms_command(e, String(data: data, encoding: .utf8)!)
        else { return ["error": "null reply"] }
        defer { pms_free(raw) }
        let reply = String(cString: raw)
        let obj = (try? JSONSerialization.jsonObject(with: Data(reply.utf8)))
            as? [String: Any] ?? [:]
        if let err = obj["error"] as? String { lastError = err }
        return obj
    }

    func render(into texture: MTLTexture) {
        guard let e = engine else { return }
        _ = pms_render(e, Unmanaged.passUnretained(texture).toOpaque(),
                       texture.width, texture.height)
    }

    private func pumpEvents(_ e: OpaquePointer) {
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
}
