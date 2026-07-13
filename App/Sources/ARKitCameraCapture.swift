import ARKit
import AVFoundation
import CoreMedia
import CoreVideo
import CoreImage
import UIKit

/// ARSession-based capture for the TrueDepth front camera. Replaces the
/// AVCapture path for the front camera on supported devices. Feeds frames to
/// the engine exactly like CameraCapture, but also submits ARKit's 1220-pt
/// face mesh + blendshapes for zero-latency makeup tracking.
final class ARKitCameraCapture: NSObject, CameraCaptureProtocol, ARSessionDelegate {
    enum CaptureError: LocalizedError {
        case notSupported
        case configuration(String)
        var errorDescription: String? {
            switch self {
            case .notSupported: return "ARKit face tracking requires a TrueDepth camera."
            case .configuration(let d): return "ARKit setup failed: \(d)"
            }
        }
    }

    private let session = ARSession()
    private let sessionQueue = DispatchQueue(label: "pms.arkit")
    private weak var engine: EngineStore?
    private let audioCapture = AudioCapture()
    private let ciContext: CIContext
    private var portraitPool: CVPixelBufferPool?
    private var portraitSize = CGSize.zero

    // Latest camera frame for tap-to-pick (chroma key colour sampling).
    private let frameLock = NSLock()
    private var latestFrame: CVPixelBuffer?

    var matteEnabled = false
    var filteredRecorder: FilteredTakeRecorder?

    private let matteQueue = DispatchQueue(label: "pms.arkit.matte", qos: .userInitiated)
    private let visionMatte = VisionMatte()
    private var matteInFlight = false
    private var lastMatteHostTime: Double = 0
    private let matteInterval = 1.0 / 30.0

    init(engine: EngineStore) {
        self.engine = engine
        ciContext = CIContext(mtlDevice: engine.device)
        super.init()
        session.delegate = self
        session.delegateQueue = sessionQueue
        audioCapture.engine = engine
        audioCapture.onSampleBuffer = { [weak self] sb in self?.handleAudioOutput(sb) }
    }

    static var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }

    /// `position`/`preset`/`orientation` are ignored for ARKit — the front
    /// TrueDepth camera is fixed portrait. We keep the same signature as
    /// CameraCapture so RecordView can switch between them.
    func start(position: AVCaptureDevice.Position = .front,
               preset: CameraCapture.CapturePreset = .hd1080,
               orientation: CameraCapture.CaptureOrientation = .portrait) throws {
        guard ARFaceTrackingConfiguration.isSupported else {
            throw CaptureError.notSupported
        }
        let configuration = ARFaceTrackingConfiguration()
        configuration.maximumNumberOfTrackedFaces = 4
        configuration.worldAlignment = .camera
        // ARSession.run must be called on the main thread.
        session.run(configuration)
        audioCapture.start()
    }

    func stop() {
        session.pause()
        audioCapture.stop()
        frameLock.lock(); latestFrame = nil; frameLock.unlock()
        engine?.submitPersonMatte(nil, hostTime: 0)
        engine?.clearContent()
    }

    func sampleColor(atNormalized pt: CGPoint) -> (r: Double, g: Double, b: Double)? {
        frameLock.lock()
        let frame = latestFrame
        frameLock.unlock()
        guard let frame else { return nil }
        CVPixelBufferLockBaseAddress(frame, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(frame, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(frame) else { return nil }
        let w = CVPixelBufferGetWidth(frame), h = CVPixelBufferGetHeight(frame)
        let stride = CVPixelBufferGetBytesPerRow(frame)
        let x = min(w - 1, max(0, Int(pt.x * CGFloat(w))))
        let y = min(h - 1, max(0, Int(pt.y * CGFloat(h))))
        let p = base.advanced(by: y * stride + x * 4).assumingMemoryBound(to: UInt8.self)
        return (Double(p[2]) / 255.0, Double(p[1]) / 255.0, Double(p[0]) / 255.0)
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let pb = portraitBGRAFrame(from: frame.capturedImage) else { return }
        let imgW = CVPixelBufferGetWidth(pb)
        let imgH = CVPixelBufferGetHeight(pb)

        frameLock.lock(); latestFrame = pb; frameLock.unlock()
        engine?.submitCameraFrame(pb, rotation: 0, hostTime: frame.timestamp)

        // Face geometry is submitted HERE, from this frame's own camera and
        // anchors, so landmarks and pixels can never desync. (The separate
        // didUpdate-anchors callback projected through a cached camera from
        // a different frame; worse, when fast motion made ARKit drop
        // tracking, anchor updates stopped but the stale landmarks kept
        // painting makeup onto fresh video — makeup floated off the face
        // until tracking recovered.)
        submitFaces(frame: frame, imgW: imgW, imgH: imgH)

        let pts = CMTime(seconds: frame.timestamp, preferredTimescale: 600)
        if let rec = filteredRecorder {
            DispatchQueue.main.async { rec.appendRenderedFrame(at: pts) }
        }
        if matteEnabled { kickMatte(pb, hostTime: frame.timestamp) }
    }

    private func submitFaces(frame: ARFrame, imgW: Int, imgH: Int) {
        // isTracked == false means ARKit lost the face (fast motion, out of
        // frame): clear the slot so the engine falls back / hides makeup
        // instead of painting with frozen geometry.
        let anchors = frame.anchors.compactMap { $0 as? ARFaceAnchor }
                                   .filter { $0.isTracked }
        guard let anchor = anchors.first else {
            engine?.clearARKitFaces()
            return
        }
        // Native tier-1 path (docs/ARKIT_NATIVE_PLAN.md): ship the full 3D
        // state — vertices in anchor space plus the transform chain and eye
        // poses — and let the engine render ARKit's mesh with ARKit's own
        // camera. No 2D projection here, no landmark bridge in the render.
        let camera = frame.camera
        let viewport = CGSize(width: imgW, height: imgH)
        let view = camera.viewMatrix(for: .portrait)
        let proj = camera.projectionMatrix(for: .portrait,
                                           viewportSize: viewport,
                                           zNear: 0.01, zFar: 10.0)
        let verts = anchor.geometry.vertices
        var packed = [Float](repeating: 0, count: verts.count * 3)
        for (i, v) in verts.enumerated() {
            packed[i * 3 + 0] = v.x
            packed[i * 3 + 1] = v.y
            packed[i * 3 + 2] = v.z
        }
        let blend = arkitBlendShapeArray(from: anchor.blendShapes)
        engine?.submitARKitFace3D(vertices: packed,
                                  model: anchor.transform,
                                  view: view, proj: proj,
                                  eyeL: anchor.leftEyeTransform,
                                  eyeR: anchor.rightEyeTransform,
                                  blendshapes: blend,
                                  width: imgW, height: imgH)
        recordFixtureFrame(frame: frame, anchor: anchor, packed: packed,
                           view: view, proj: proj, blend: blend,
                           imgW: imgW, imgH: imgH)
    }

    // MARK: fixture capture (ARKIT_NATIVE_PLAN Phase 0)
    // Dumps per-frame geometry to Documents/arkit_capture_<ts>.jsonl so the
    // Mac replay harness can regression-test against real faces in motion.
    private var captureRemaining = 0
    private var captureHandle: FileHandle?

    func startFixtureCapture(frames: Int = 180) {
        let dir = FileManager.default.urls(for: .documentDirectory,
                                           in: .userDomainMask)[0]
        let ts = Int(Date().timeIntervalSince1970)
        let url = dir.appendingPathComponent("arkit_capture_\(ts).jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        captureHandle = try? FileHandle(forWritingTo: url)
        captureRemaining = captureHandle != nil ? frames : 0
    }

    private func recordFixtureFrame(frame: ARFrame, anchor: ARFaceAnchor,
                                    packed: [Float], view: simd_float4x4,
                                    proj: simd_float4x4, blend: [Float],
                                    imgW: Int, imgH: Int) {
        guard captureRemaining > 0, let handle = captureHandle else { return }
        captureRemaining -= 1
        func flat(_ m: simd_float4x4) -> [Float] {
            var out = [Float]()
            for c in 0..<4 { let col = m[c]
                out.append(contentsOf: [col.x, col.y, col.z, col.w]) }
            return out
        }
        let rec: [String: Any] = [
            "t": frame.timestamp, "w": imgW, "h": imgH,
            "verts": packed.map { Double($0) },
            "model": flat(anchor.transform).map { Double($0) },
            "view": flat(view).map { Double($0) },
            "proj": flat(proj).map { Double($0) },
            "eye_l": flat(anchor.leftEyeTransform).map { Double($0) },
            "eye_r": flat(anchor.rightEyeTransform).map { Double($0) },
            "blend": blend.map { Double($0) },
        ]
        if let data = try? JSONSerialization.data(withJSONObject: rec),
           let line = String(data: data, encoding: .utf8) {
            handle.write(Data((line + "\n").utf8))
        }
        if captureRemaining == 0 {
            try? captureHandle?.close()
            captureHandle = nil
        }
    }

    /// ARKit supplies bi-planar Y'CbCr frames in landscape sensor orientation.
    /// The engine accepts one-plane BGRA textures only, so map and rotate here
    /// rather than interpreting Y as four BGRA pixels in the Metal compositor.
    ///
    /// Coordinate contract: portrait is UNMIRRORED. Person's left lands on
    /// the RIGHT of the buffer (larger X). The engine's ARKit→MediaPipe
    /// correspondence (generated arkit_mp_map.h) is index-based and
    /// anatomical, so makeup stays correct under any convention — but the
    /// frame and the projected mesh below MUST use the same one. If you ever
    /// mirror this buffer (selfie preview), mirror projectPoint results too.
    private func portraitBGRAFrame(from source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetHeight(source)
        let height = CVPixelBufferGetWidth(source)
        let size = CGSize(width: width, height: height)
        if portraitPool == nil || portraitSize != size {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
            var pool: CVPixelBufferPool?
            guard CVPixelBufferPoolCreate(kCFAllocatorDefault, nil,
                                          attributes as CFDictionary, &pool) == kCVReturnSuccess else {
                return nil
            }
            portraitPool = pool
            portraitSize = size
        }

        guard let portraitPool else { return nil }
        var output: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, portraitPool, &output) == kCVReturnSuccess,
              let output else { return nil }

        let portrait = CIImage(cvPixelBuffer: source).oriented(.right)
        let bounds = CGRect(origin: .zero, size: size)
        let normalized = portrait.transformed(by: .init(translationX: -portrait.extent.minX,
                                                         y: -portrait.extent.minY))
        ciContext.render(normalized, to: output, bounds: bounds,
                         colorSpace: CGColorSpaceCreateDeviceRGB())
        return output
    }

    // MARK: audio passthrough to take writer / filtered recorder

    private func handleAudioOutput(_ sampleBuffer: CMSampleBuffer) {
        if let rec = filteredRecorder { rec.appendAudio(sampleBuffer) }
    }

    // MARK: take recording
    // RecordView uses FilteredTakeRecorder for WYSIWYG captures; the raw
    // AVAssetWriter path is not currently wired for ARFrame CVPixelBuffers.
    private var takeURL: URL?
    func startTake(to url: URL) throws {
        takeURL = url
    }
    func stopTake(completion: @escaping (URL?) -> Void) {
        takeURL = nil
        completion(nil)
    }

    // MARK: person matte (Vision, bounded cadence, own queue)

    private func kickMatte(_ frame: CVPixelBuffer, hostTime: Double) {
        guard !matteInFlight, hostTime - lastMatteHostTime >= matteInterval else { return }
        matteInFlight = true
        lastMatteHostTime = hostTime
        matteQueue.async { [weak self] in
            guard let self else { return }
            let recording = self.filteredRecorder != nil
            self.visionMatte.quality = recording ? .accurate : .balanced
            let matte = self.visionMatte.matte(for: frame)
            self.engine?.submitPersonMatte(matte, hostTime: hostTime)
            self.sessionQueue.async { self.matteInFlight = false }
        }
    }
}
