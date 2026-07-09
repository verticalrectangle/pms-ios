// CameraCapture.swift — AVFoundation capture feeding the engine intake.
// Replaces the desktop V4L2/ffmpeg-child path. Frames go to the engine as
// CVPixelBuffers (zero-copy into Metal via the engine's texture cache).
// Frames are rotated to upright portrait AT THE CONNECTION (videoRotationAngle),
// so the engine is told rotation 0 — no second rotation from device orientation.
import AVFoundation
import UIKit
import CoreMedia

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

    // Mic → engine capture-injection ring (AVAudioConverter per input format).
    private var audioConverter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?

    // Person matte: bounded-cadence Vision segmentation on its own queue so
    // inference never stalls frame delivery.
    var matteEnabled = false
    private let matteQueue = DispatchQueue(label: "pms.matte", qos: .userInitiated)
    private let visionMatte = VisionMatte()
    private var matteInFlight = false
    private var lastMatteHostTime: Double = 0
    private let matteInterval = 1.0 / 15.0   // ≤15 fps preview segmentation

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
        engine?.submitPersonMatte(nil, hostTime: 0)
        engine?.clearContent()
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if output is AVCaptureAudioDataOutput {
            submitMic(sampleBuffer)
            return
        }
        // Video frames → the engine's Metal compositor (live canvas preview).
        guard output is AVCaptureVideoDataOutput,
              let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let host = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        engine?.submitCameraFrame(pb, rotation: needsEngineRotation ? 1 : 0, hostTime: host)
        if matteEnabled { kickMatte(pb, hostTime: host) }
    }

    // MARK: mic → engine (interleaved stereo Float32 via AVAudioConverter)

    private func submitMic(_ sb: CMSampleBuffer) {
        guard let desc = CMSampleBufferGetFormatDescription(sb) else { return }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sb))
        guard frames > 0 else { return }
        let inFormat = AVAudioFormat(cmAudioFormatDescription: desc)

        guard let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frames) else { return }
        inBuf.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sb, at: 0, frameCount: Int32(frames),
            into: inBuf.mutableAudioBufferList) == noErr else { return }

        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: inFormat.sampleRate,
                                            channels: 2, interleaved: true) else { return }
        if audioConverter == nil || converterInputFormat != inFormat {
            audioConverter = AVAudioConverter(from: inFormat, to: outFormat)
            converterInputFormat = inFormat
        }
        guard let converter = audioConverter,
              let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: frames) else { return }

        var fed = false
        let status = converter.convert(to: outBuf, error: nil) { _, outStatus in
            if fed { outStatus.pointee = .noDataNow; return nil }
            fed = true
            outStatus.pointee = .haveData
            return inBuf
        }
        guard status != .error, outBuf.frameLength > 0,
              let data = outBuf.floatChannelData?[0] else { return }
        // Engine resamples to its 44.1 kHz internally; pass the native rate.
        engine?.submitMicBlock(data, frames: Int(outBuf.frameLength),
                               sampleRate: outFormat.sampleRate)
    }

    // MARK: person matte (Vision, bounded cadence, own queue)

    private func kickMatte(_ frame: CVPixelBuffer, hostTime: Double) {
        guard !matteInFlight, hostTime - lastMatteHostTime >= matteInterval else { return }
        matteInFlight = true
        lastMatteHostTime = hostTime
        matteQueue.async { [weak self] in
            guard let self else { return }
            let matte = self.visionMatte.matte(for: frame)
            self.engine?.submitPersonMatte(matte, hostTime: hostTime)
            self.videoQueue.async { self.matteInFlight = false }
        }
    }
}
