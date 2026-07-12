import AVFoundation
import CoreMedia

/// Shared mic capture helper. Can be the AVCaptureAudioDataOutput delegate for
/// a standalone audio-only session (ARKit path) or be called by a host capture
/// class that already owns the audio output (AVCapture camera path).
final class AudioCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    weak var engine: EngineStore?

    /// Called on the audio queue after the block has been submitted to the
    /// engine. Use it to append audio to a take writer / filtered recorder.
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    let audioQueue = DispatchQueue(label: "pms.mic")
    private var audioConverter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private var session: AVCaptureSession?
    private var output: AVCaptureAudioDataOutput?

    init(engine: EngineStore? = nil) {
        self.engine = engine
        super.init()
    }

    /// Start a standalone audio-only AVCaptureSession (used by ARKit path).
    func start() {
        audioQueue.async { [weak self] in
            guard let self else { return }
            let session = AVCaptureSession()
            self.session = session
            guard let mic = AVCaptureDevice.default(for: .audio) else { return }
            do {
                session.addInput(try AVCaptureDeviceInput(device: mic))
            } catch { return }
            let output = AVCaptureAudioDataOutput()
            output.setSampleBufferDelegate(self, queue: self.audioQueue)
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            self.output = output
            session.startRunning()
        }
    }

    func stop() {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.session?.stopRunning()
            self.session = nil
            self.output = nil
            self.audioConverter = nil
            self.converterInputFormat = nil
        }
    }

    /// Convert and submit one audio sample buffer to the engine; optionally
    /// forward it to a take writer/recorder via `onSampleBuffer`.
    func processAudioSampleBuffer(_ sb: CMSampleBuffer) {
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
        engine?.submitMicBlock(data, frames: Int(outBuf.frameLength),
                               sampleRate: outFormat.sampleRate)
        onSampleBuffer?(sb)
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        processAudioSampleBuffer(sampleBuffer)
    }
}
