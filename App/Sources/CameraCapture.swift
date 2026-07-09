// CameraCapture.swift — AVFoundation capture feeding the engine intake.
// Replaces the desktop V4L2/ffmpeg-child path. Frames go to the engine as
// CVPixelBuffers (zero-copy into Metal via the engine's texture cache).
// Frames are rotated to upright portrait AT THE CONNECTION (videoRotationAngle),
// so the engine is told rotation 0 — no second rotation from device orientation.
import AVFoundation
import UIKit

final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
                           AVCaptureAudioDataOutputSampleBufferDelegate {
    enum CaptureError: LocalizedError {
        case cameraDenied
        case micDenied
        case noDevices
        case configuration(String)
        var errorDescription: String? {
            switch self {
            case .cameraDenied: return "Camera access is denied — enable it in Settings to record."
            case .micDenied:    return "Microphone access is denied — enable it in Settings to record."
            case .noDevices:    return "No capture devices available."
            case .configuration(let d): return "Camera setup failed: \(d)"
            }
        }
    }

    private let session = AVCaptureSession()
    private let videoQueue = DispatchQueue(label: "pms.camera")
    private let audioQueue = DispatchQueue(label: "pms.mic")
    private weak var engine: EngineStore?
    // Outputs are created once and kept — repeated start()s reconfigure inputs
    // only, never stack duplicate outputs.
    private var videoOutput: AVCaptureVideoDataOutput?
    private var audioOutput: AVCaptureAudioDataOutput?
    /// True when the connection could not rotate to portrait — then (and only
    /// then) the engine is told to rotate.
    private var needsEngineRotation = false

    init(engine: EngineStore) { self.engine = engine }

    /// Request camera + mic authorization. Completion on main.
    static func requestAuthorization(_ completion: @escaping (Result<Void, CaptureError>) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { cam in
            guard cam else { return DispatchQueue.main.async { completion(.failure(.cameraDenied)) } }
            AVCaptureDevice.requestAccess(for: .audio) { mic in
                DispatchQueue.main.async {
                    completion(mic ? .success(()) : .failure(.micDenied))
                }
            }
        }
    }

    func start(position: AVCaptureDevice.Position = .front) throws {
        session.beginConfiguration()
        var committed = false
        defer { if !committed { session.commitConfiguration() } }   // failure-safe cleanup

        session.sessionPreset = .hd1280x720           // tracker-friendly; takes record at this res
        session.inputs.forEach(session.removeInput)
        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                for: .video, position: position),
              let mic = AVCaptureDevice.default(for: .audio) else {
            throw CaptureError.noDevices
        }
        do {
            session.addInput(try AVCaptureDeviceInput(device: cam))
            session.addInput(try AVCaptureDeviceInput(device: mic))
        } catch {
            throw CaptureError.configuration(error.localizedDescription)
        }

        if videoOutput == nil {
            let video = AVCaptureVideoDataOutput()
            video.videoSettings =
                [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            video.alwaysDiscardsLateVideoFrames = true    // live mirror: latest wins
            video.setSampleBufferDelegate(self, queue: videoQueue)
            guard session.canAddOutput(video) else { throw CaptureError.configuration("video output rejected") }
            session.addOutput(video)
            videoOutput = video
        }
        if audioOutput == nil {
            let audio = AVCaptureAudioDataOutput()
            audio.setSampleBufferDelegate(self, queue: audioQueue)
            guard session.canAddOutput(audio) else { throw CaptureError.configuration("audio output rejected") }
            session.addOutput(audio)
            audioOutput = audio
        }

        // Output upright PORTRAIT frames (the sensor is landscape). 90° gives a
        // 720×1280 buffer that fills the 9:16 canvas; mirror the front camera.
        needsEngineRotation = true
        if let conn = videoOutput?.connection(with: .video) {
            if conn.isVideoRotationAngleSupported(90) {
                conn.videoRotationAngle = 90
                needsEngineRotation = false
            }
            if conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = false
                conn.isVideoMirrored = (position == .front)
            }
        }

        session.commitConfiguration()
        committed = true
        videoQueue.async { self.session.startRunning() }
    }

    func stop() {
        videoQueue.async { self.session.stopRunning() }
        engine?.clearContent()
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Video frames → the engine's Metal compositor (live canvas preview).
        // Mic blocks route through pms_submit_mic_block once the ABI-2 engine
        // lands (Slice C); until then audio is captured but not injected.
        guard output is AVCaptureVideoDataOutput,
              let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let host = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        engine?.submitCameraFrame(pb, rotation: needsEngineRotation ? 1 : 0, hostTime: host)
    }
}
