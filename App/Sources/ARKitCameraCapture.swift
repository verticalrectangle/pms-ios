import ARKit
import AVFoundation
import CoreMedia
import CoreVideo
import CoreImage
import ImageIO
import UIKit
import UniformTypeIdentifiers

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
        // One face: ARKit then tracks the most prominent face, and the engine
        // renders exactly one makeup mesh.
        configuration.maximumNumberOfTrackedFaces = 1
        // Per-frame ARDirectionalLightEstimate (primary light + SH) — recorded
        // in fixtures; drives gloss/highlight response to the real light.
        configuration.isLightEstimationEnabled = true
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
        submitFaces(frame: frame, pixels: pb, imgW: imgW, imgH: imgH)

        let pts = CMTime(seconds: frame.timestamp, preferredTimescale: 600)
        if let rec = filteredRecorder {
            DispatchQueue.main.async { rec.appendRenderedFrame(at: pts) }
        }
        if matteEnabled { kickMatte(pb, hostTime: frame.timestamp) }
    }

    private func submitFaces(frame: ARFrame, pixels: CVPixelBuffer, imgW: Int, imgH: Int) {
        // isTracked == false means ARKit lost the face (fast motion, out of
        // frame): clear the slot so the engine hides makeup instead of
        // painting with frozen geometry.
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
                                  blendshapes: blend,
                                  light: Self.engineLight(frame.lightEstimate),
                                  width: imgW, height: imgH)
        if let fixture, fixture.record(frame: frame, anchor: anchor, pixels: pixels,
                                       packed: packed, view: view, proj: proj,
                                       blend: blend) {
            self.fixture = nil
        }
    }

    /// ARFrame.lightEstimate → the engine's light record. Face tracking
    /// delivers an ARDirectionalLightEstimate (primary light + SH), which
    /// drives gloss and highlighter; otherwise only the ambient terms.
    private static func engineLight(_ estimate: ARLightEstimate?) -> pms_arkit_light {
        var l = pms_arkit_light()
        l.ambient_intensity = Float(estimate?.ambientIntensity ?? 1000)
        l.ambient_kelvin = Float(estimate?.ambientColorTemperature ?? 6500)
        guard let d = estimate as? ARDirectionalLightEstimate else { return l }
        let dir = d.primaryLightDirection
        l.primary_dir = (dir.x, dir.y, dir.z)
        l.primary_intensity = Float(d.primaryLightIntensity)
        withUnsafeMutableBytes(of: &l.sh) { dst in
            d.sphericalHarmonicsCoefficients.withUnsafeBytes { src in
                dst.copyMemory(from: UnsafeRawBufferPointer(rebasing: src.prefix(dst.count)))
            }
        }
        l.directional = 1
        return l
    }

    // MARK: fixture capture
    // Triple-tap in RecordView records a real-face fixture for the engine's Mac
    // replay harness (tools/arkit_native_replay.mm): Documents/arkit_capture_<ts>/
    // holds frames.jsonl — one line per recorded ARFrame: geometry, transform
    // chain, eye poses, blendshapes, light estimate, exposure — and fNNNN.jpg,
    // the exact portrait BGRA frame the engine received for that ARFrame. Replay
    // composites makeup onto these real frames with their own geometry.
    private var fixture: FixtureCapture?   // session queue only

    /// Record `frames` fixture frames from every `stride`-th tracked ARFrame
    /// (ARKit delivers 60 fps; stride 2 = 30 fps). Ignored while a capture is
    /// running. `onFinish` runs on the main queue once every JPEG is on disk.
    func startFixtureCapture(frames: Int = 300, stride: Int = 2,
                             onFinish: @escaping (URL, Int) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self, self.fixture == nil else { return }
            self.fixture = FixtureCapture(frames: frames, stride: stride) { dir, written in
                DispatchQueue.main.async { onFinish(dir, written) }
            }
        }
    }

    /// ARKit supplies bi-planar Y'CbCr frames in landscape sensor orientation.
    /// The engine accepts one-plane BGRA textures only, so map and rotate here
    /// rather than interpreting Y as four BGRA pixels in the Metal compositor.
    ///
    /// Coordinate contract: portrait is UNMIRRORED. Person's left lands on
    /// the RIGHT of the buffer (larger X). The engine renders the face mesh
    /// with this frame's own `.portrait` view/projection matrices, so the
    /// buffer and the matrices MUST share one convention: if you ever mirror
    /// this buffer (selfie preview), mirror the projection too.
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

private final class FixtureCapture {
    private let dir: URL
    private let handle: FileHandle
    private let encodeQueue = DispatchQueue(label: "pms.arkit.fixture", qos: .utility)
    private let lock = NSLock()
    private var pendingEncodes = 0          // guarded by lock
    private var remaining: Int
    private let stride: Int
    private var seen = 0
    private var written = 0
    private let onFinish: (URL, Int) -> Void
    /// Each pending encode holds a ~6 MB frame copy; past this many the frame's
    /// geometry is still recorded but its image is skipped ("img" absent).
    private static let maxPendingEncodes = 8

    init?(frames: Int, stride: Int, onFinish: @escaping (URL, Int) -> Void) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("arkit_capture_\(Int(Date().timeIntervalSince1970))",
                                          isDirectory: true)
        let jsonl = dir.appendingPathComponent("frames.jsonl")
        guard (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil,
              FileManager.default.createFile(atPath: jsonl.path, contents: nil),
              let h = try? FileHandle(forWritingTo: jsonl) else { return nil }
        handle = h
        remaining = max(1, frames)
        self.stride = max(1, stride)
        self.onFinish = onFinish
    }

    /// Records one ARFrame (subject to the stride). Returns true once the
    /// capture has written its last frame; the caller then drops it.
    func record(frame: ARFrame, anchor: ARFaceAnchor, pixels: CVPixelBuffer,
                packed: [Float], view: simd_float4x4, proj: simd_float4x4,
                blend: [Float]) -> Bool {
        defer { seen += 1 }
        guard seen % stride == 0 else { return false }
        func flat(_ m: simd_float4x4) -> [Double] {
            (0..<4).flatMap { c in [m[c].x, m[c].y, m[c].z, m[c].w].map(Double.init) }
        }
        var rec: [String: Any] = [
            "t": frame.timestamp,
            "w": CVPixelBufferGetWidth(pixels), "h": CVPixelBufferGetHeight(pixels),
            "verts": packed.map(Double.init),
            "model": flat(anchor.transform),
            "view": flat(view),
            "proj": flat(proj),
            "eye_l": flat(anchor.leftEyeTransform),
            "eye_r": flat(anchor.rightEyeTransform),
            "blend": blend.map(Double.init),
            "exposure": ["duration": frame.camera.exposureDuration,
                         "offset": Double(frame.camera.exposureOffset)],
        ]
        if let le = frame.lightEstimate as? ARDirectionalLightEstimate {
            let d = le.primaryLightDirection
            let sh = le.sphericalHarmonicsCoefficients.withUnsafeBytes {
                $0.bindMemory(to: Float.self).map(Double.init)
            }
            rec["light"] = ["dir": [Double(d.x), Double(d.y), Double(d.z)],
                            "intensity": Double(le.primaryLightIntensity),
                            "ambient": Double(le.ambientIntensity),
                            "kelvin": Double(le.ambientColorTemperature),
                            "sh": sh]
        } else if let le = frame.lightEstimate {
            rec["light"] = ["ambient": Double(le.ambientIntensity),
                            "kelvin": Double(le.ambientColorTemperature)]
        }
        if let name = enqueueJPEG(pixels, name: String(format: "f%04d.jpg", written)) {
            rec["img"] = name
        }
        if let data = try? JSONSerialization.data(withJSONObject: rec) {
            handle.write(data)
            handle.write(Data("\n".utf8))
        }
        written += 1
        remaining -= 1
        guard remaining == 0 else { return false }
        try? handle.close()
        let dir = dir, n = written, done = onFinish
        encodeQueue.async { done(dir, n) }   // serial: runs after the last encode
        return true
    }

    private func enqueueJPEG(_ pb: CVPixelBuffer, name: String) -> String? {
        lock.lock()
        let busy = pendingEncodes >= Self.maxPendingEncodes
        if !busy { pendingEncodes += 1 }
        lock.unlock()
        guard !busy else { return nil }
        // Copy now: the BGRA buffer comes from a pool the next ARFrame reuses.
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        let bpr = CVPixelBufferGetBytesPerRow(pb)
        let bytes = CVPixelBufferGetBaseAddress(pb).map { Data(bytes: $0, count: bpr * h) }
        CVPixelBufferUnlockBaseAddress(pb, .readOnly)
        guard let bytes else {
            lock.lock(); pendingEncodes -= 1; lock.unlock()
            return nil
        }
        let url = dir.appendingPathComponent(name)
        encodeQueue.async { [self] in
            Self.writeJPEG(bytes, width: w, height: h, bytesPerRow: bpr, to: url)
            lock.lock(); pendingEncodes -= 1; lock.unlock()
        }
        return name
    }

    /// BGRA (little-endian, alpha ignored) → sRGB-tagged JPEG. The engine
    /// treats these bytes as sRGB-encoded, so the replay sees the same values.
    private static func writeJPEG(_ bytes: Data, width: Int, height: Int,
                                  bytesPerRow: Int, to url: URL) {
        guard let provider = CGDataProvider(data: bytes as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8,
                                  bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                                           | CGBitmapInfo.byteOrder32Little.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString,
                                                         1, nil) else { return }
        CGImageDestinationAddImage(dest, image,
                                   [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }
}
