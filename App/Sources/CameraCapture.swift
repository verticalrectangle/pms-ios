// CameraCapture.swift — AVFoundation capture feeding the engine intake.
// Replaces the desktop V4L2/ffmpeg-child path. Frames go to the engine as
// CVPixelBuffers (zero-copy into Metal via the engine's texture cache);
// device orientation maps onto the engine's quarter-turn plumbing — the
// tracker's roll ladder handles everything in between.
import AVFoundation
import UIKit

final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
                           AVCaptureAudioDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let videoQueue = DispatchQueue(label: "pms.camera")
    private let audioQueue = DispatchQueue(label: "pms.mic")
    private weak var engine: EngineStore?

    init(engine: EngineStore) { self.engine = engine }

    func start(position: AVCaptureDevice.Position = .front) throws {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720           // tracker-friendly; takes record at this res
        session.inputs.forEach(session.removeInput)
        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                for: .video, position: position),
              let mic = AVCaptureDevice.default(for: .audio) else {
            throw NSError(domain: "pms", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "no capture devices"])
        }
        session.addInput(try AVCaptureDeviceInput(device: cam))
        session.addInput(try AVCaptureDeviceInput(device: mic))

        let video = AVCaptureVideoDataOutput()
        video.videoSettings =
            [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        video.alwaysDiscardsLateVideoFrames = true    // live mirror: latest wins
        video.setSampleBufferDelegate(self, queue: videoQueue)
        session.addOutput(video)

        let audio = AVCaptureAudioDataOutput()
        audio.setSampleBufferDelegate(self, queue: audioQueue)
        session.addOutput(audio)
        session.commitConfiguration()
        videoQueue.async { self.session.startRunning() }
    }

    func stop() { session.stopRunning() }

    private var rotationQuarterTurns: Int {
        switch UIDevice.current.orientation {
        case .landscapeLeft: return 1
        case .portraitUpsideDown: return 2
        case .landscapeRight: return 3
        default: return 0
        }
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Video frames → the engine's Metal compositor (live canvas preview).
        // Audio (pms_submit_mic_block) lands with the record path.
        guard output is AVCaptureVideoDataOutput,
              let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let host = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        engine?.submitCameraFrame(pb, rotation: Int32(rotationQuarterTurns), hostTime: host)
    }
}
