import ARKit
import AVFoundation
import CoreMedia
import CoreVideo
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

    private let cameraLock = NSLock()
    private var latestCamera: ARCamera?
    private var cachedImageWidth: Int = 0
    private var cachedImageHeight: Int = 0

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
        let pb = frame.capturedImage
        let imgW = CVPixelBufferGetWidth(pb)
        let imgH = CVPixelBufferGetHeight(pb)

        cameraLock.lock()
        latestCamera = frame.camera
        cachedImageWidth = imgW
        cachedImageHeight = imgH
        cameraLock.unlock()

        frameLock.lock(); latestFrame = pb; frameLock.unlock()
        engine?.submitCameraFrame(pb, rotation: 0, hostTime: frame.timestamp)

        let pts = CMTime(seconds: frame.timestamp, preferredTimescale: 600)
        if let rec = filteredRecorder {
            DispatchQueue.main.async { rec.appendRenderedFrame(at: pts) }
        }
        if matteEnabled { kickMatte(pb, hostTime: frame.timestamp) }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        cameraLock.lock()
        let camera = latestCamera
        let imgW = cachedImageWidth
        let imgH = cachedImageHeight
        cameraLock.unlock()
        guard let camera = camera else { return }

        let viewport = CGSize(width: imgW, height: imgH)
        for anchor in anchors.compactMap({ $0 as? ARFaceAnchor }) {
            let vertices = UnsafeMutablePointer<Float>.allocate(capacity: 1220 * 2)
            for (i, vertex) in anchor.geometry.vertices.enumerated() {
                let world = anchor.transform * SIMD4<Float>(vertex, 1)
                let projected = camera.projectPoint(
                    SIMD3<Float>(world.x, world.y, world.z),
                    orientation: .portrait,
                    viewportSize: viewport
                )
                vertices[i * 2] = Float(projected.x)
                vertices[i * 2 + 1] = Float(projected.y)
            }
            let blend = arkitBlendShapeArray(from: anchor.blendShapes)
            blend.withUnsafeBufferPointer { blendPtr in
                engine?.submitARKitFace(vertices: vertices,
                                        blendshapes: blendPtr.baseAddress!,
                                        count: 1,
                                        width: imgW,
                                        height: imgH)
            }
            vertices.deallocate()
        }
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
