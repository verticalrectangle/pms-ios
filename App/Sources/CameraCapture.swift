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
    enum CapturePreset {
        case hd720, hd1080, hd4K
        var avPreset: AVCaptureSession.Preset {
            switch self {
            case .hd720:  return AVCaptureSession.Preset.hd1280x720
            case .hd1080: return AVCaptureSession.Preset.hd1920x1080
            case .hd4K:   return AVCaptureSession.Preset.hd4K3840x2160
            }
        }
    }

    enum CaptureOrientation {
        case portrait, landscape  // portrait = rotate sensor 90°, landscape = sensor-native 0°
    }

    static func recordingBitrate(width: Int, height: Int) -> Int {
        min(max(width * height * 6, 8_000_000), 12_000_000)
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

    // Thermal / low-power adaptation state.
    private var thermalObserver: NSObjectProtocol?
    private var powerObserver: NSObjectProtocol?
    private var currentPreset: CapturePreset = .hd1080
    private var currentPosition: AVCaptureDevice.Position = .front
    private var currentOrientation: CaptureOrientation = .portrait

    // Mic → engine capture-injection ring (AVAudioConverter per input format).
    private var audioConverter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?

    // Latest camera frame, retained for tap-to-sample (chroma key picking).
    private let frameLock = NSLock()
    private var latestFrame: CVPixelBuffer?

    /// Sample the BGRA pixel at normalized buffer coords (0–1, top-left
    /// origin). Returns 0–1 RGB. Thread-safe; nil before the first frame.
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
        // BGRA byte order.
        return (Double(p[2]) / 255.0, Double(p[1]) / 255.0, Double(p[0]) / 255.0)
    }

    // Person matte: bounded-cadence Vision segmentation on its own queue so
    // inference never stalls frame delivery.
    var matteEnabled = false
    private let matteQueue = DispatchQueue(label: "pms.matte", qos: .userInitiated)
    private let visionMatte = VisionMatte()
    private var matteInFlight = false
    private var lastMatteHostTime: Double = 0
    private let matteInterval = 1.0 / 15.0   // ≤15 fps preview segmentation

    // Filtered take (record mode): when set, video frames are re-rendered
    // through the engine and encoded by the recorder (WYSIWYG — looks baked
    // into the pixels); audio passes through to it. The raw startTake path
    // below stays for unfiltered captures.
    var filteredRecorder: FilteredTakeRecorder?

    // Take recording: AVAssetWriter muxes the same delegate sample buffers
    // (video h264, mic AAC) into a .mov in the project's media dir. iOS owns
    // muxing; the engine gets the finished file (bin + clip).
    private let takeLock = NSLock()
    private var takeWriter: AVAssetWriter?
    private var takeVideoIn: AVAssetWriterInput?
    private var takeAudioIn: AVAssetWriterInput?
    private var takeSessionStarted = false

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

    func start(position: AVCaptureDevice.Position = .front,
               preset: CapturePreset = .hd1080,
               orientation: CaptureOrientation = .portrait) throws {
        currentPosition = position
        currentOrientation = orientation

        session.beginConfiguration()
        var committed = false
        defer { if !committed { session.commitConfiguration() } }   // failure-safe cleanup

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

        // Low-light boost helps contour tracking in dim scenes. Non-fatal.
        do {
            try cam.lockForConfiguration()
            if cam.isLowLightBoostSupported {
                cam.automaticallyEnablesLowLightBoostWhenAvailable = true
            }
            cam.unlockForConfiguration()
        } catch {
            // Continue with default exposure.
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

        // Pick the highest preset the active camera supports, with a safe fallback.
        func resolvePreset(_ preset: CapturePreset) throws -> CapturePreset {
            let candidates: [CapturePreset]
            switch preset {
            case .hd4K:   candidates = [.hd4K, .hd1080, .hd720]
            case .hd1080: candidates = [.hd1080, .hd720]
            case .hd720:  candidates = [.hd720]
            }
            for p in candidates {
                if session.canSetSessionPreset(p.avPreset) { return p }
            }
            throw CaptureError.configuration("camera does not support \(preset.avPreset.rawValue)")
        }
        let chosen = try resolvePreset(preset)
        currentPreset = chosen
        session.sessionPreset = chosen.avPreset

        // Rotate to portrait for .portrait/.square (face fills more frame);
        // sensor-native landscape for .landscape. Mirror the front camera.
        let shouldRotate = (orientation == .portrait)
        needsEngineRotation = true
        if let conn = videoOutput?.connection(with: .video) {
            let angle: CGFloat = shouldRotate ? 90 : 0
            if conn.isVideoRotationAngleSupported(angle) {
                conn.videoRotationAngle = angle
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

        if thermalObserver == nil {
            startThermalMonitoring()
        }
    }

    func stop() {
        if thermalObserver != nil { NotificationCenter.default.removeObserver(thermalObserver!); thermalObserver = nil }
        if powerObserver != nil { NotificationCenter.default.removeObserver(powerObserver!); powerObserver = nil }
        if takeWriter != nil { stopTake { _ in } }   // never leave a writer dangling
        if let rec = filteredRecorder { filteredRecorder = nil; rec.finish { _ in } }
        videoQueue.async { self.session.stopRunning() }
        frameLock.lock(); latestFrame = nil; frameLock.unlock()
        engine?.submitPersonMatte(nil, hostTime: 0)
        engine?.clearContent()
    }

    // MARK: thermal / power adaptation

    private func startThermalMonitoring() {
        let nc = NotificationCenter.default
        thermalObserver = nc.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                                         object: nil, queue: nil) { [weak self] _ in
            self?.adaptToConditions()
        }
        powerObserver = nc.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange,
                                       object: nil, queue: nil) { [weak self] _ in
            self?.adaptToConditions()
        }
        adaptToConditions()
    }

    private func adaptToConditions() {
        let info = ProcessInfo.processInfo
        let stressed = info.thermalState == .serious || info.thermalState == .critical
                    || info.isLowPowerModeEnabled
        let target: CapturePreset = stressed ? .hd720 : .hd1080
        guard target != currentPreset else { return }
        currentPreset = target
        // Reconfigure on the video queue — don't stop the session.
        videoQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            if self.session.canSetSessionPreset(target.avPreset) {
                self.session.sessionPreset = target.avPreset
            }
            self.session.commitConfiguration()
        }
    }

    // MARK: take recording

    func startTake(to url: URL) throws {
        takeLock.lock(); defer { takeLock.unlock() }
        guard takeWriter == nil else { return }
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let (w, h): (Int, Int) = {
            frameLock.lock(); defer { frameLock.unlock() }
            if let frame = latestFrame {
                return (CVPixelBufferGetWidth(frame), CVPixelBufferGetHeight(frame))
            }
            return (1080, 1920)
        }()
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w, AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: CameraCapture.recordingBitrate(width: w, height: h)],
        ])
        video.expectsMediaDataInRealTime = true
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1, AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 96_000,
        ])
        audio.expectsMediaDataInRealTime = true
        guard writer.canAdd(video), writer.canAdd(audio) else {
            throw CaptureError.configuration("take writer rejected inputs")
        }
        writer.add(video); writer.add(audio)
        guard writer.startWriting() else {
            throw CaptureError.configuration("take writer: \(writer.error?.localizedDescription ?? "could not start")")
        }
        takeSessionStarted = false
        takeVideoIn = video
        takeAudioIn = audio
        takeWriter = writer   // set last — the delegate checks this
    }

    /// Finish the take; completion (main queue) gets the file URL or nil.
    func stopTake(completion: @escaping (URL?) -> Void) {
        takeLock.lock()
        guard let writer = takeWriter else { takeLock.unlock(); return completion(nil) }
        let video = takeVideoIn, audio = takeAudioIn
        takeWriter = nil; takeVideoIn = nil; takeAudioIn = nil
        takeLock.unlock()
        video?.markAsFinished()
        audio?.markAsFinished()
        writer.finishWriting {
            let ok = writer.status == .completed
            DispatchQueue.main.async { completion(ok ? writer.outputURL : nil) }
        }
    }

    private func appendTake(_ sb: CMSampleBuffer, isVideo: Bool) {
        takeLock.lock(); defer { takeLock.unlock() }
        guard let writer = takeWriter, writer.status == .writing else { return }
        // Session clock starts on the first VIDEO frame so audio never leads
        // a black frame.
        if !takeSessionStarted {
            guard isVideo else { return }
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sb))
            takeSessionStarted = true
        }
        let input = isVideo ? takeVideoIn : takeAudioIn
        if let input, input.isReadyForMoreMediaData { input.append(sb) }
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if output is AVCaptureAudioDataOutput {
            submitMic(sampleBuffer)
            if let rec = filteredRecorder { rec.appendAudio(sampleBuffer) }
            else { appendTake(sampleBuffer, isVideo: false) }
            return
        }
        // Video frames → the engine's Metal compositor (live canvas preview).
        guard output is AVCaptureVideoDataOutput,
              let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts  = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let host = pts.seconds
        frameLock.lock(); latestFrame = pb; frameLock.unlock()
        engine?.submitCameraFrame(pb, rotation: needsEngineRotation ? 1 : 0, hostTime: host)
        if let rec = filteredRecorder {
            // Filtered take: render THROUGH the engine on the render thread
            // (main), after this frame's submit; encoder gates drop when busy.
            DispatchQueue.main.async { rec.appendRenderedFrame(at: pts) }
        } else {
            appendTake(sampleBuffer, isVideo: true)
        }
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
            let recording = self.filteredRecorder != nil
            self.visionMatte.quality = recording ? .accurate : .balanced
            let matte = self.visionMatte.matte(for: frame)
            self.engine?.submitPersonMatte(matte, hostTime: hostTime)
            self.videoQueue.async { self.matteInFlight = false }
        }
    }
}
