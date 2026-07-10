// FilteredTakeRecorder.swift — WYSIWYG take recording. Instead of muxing the
// raw camera sample buffers (CameraCapture.startTake), each camera frame is
// re-rendered THROUGH the engine (camera → live-FX stack → Metal) into a
// pooled CVPixelBuffer and encoded — so makeup looks, matte-keyed chroma
// trails, and every other live filter land IN THE PIXELS of the .mov, exactly
// as previewed. Audio passes through from the capture delegate untouched.
//
// Render + append run on the main queue (pms_render's thread), gated by the
// writer's readiness — a busy frame drops rather than stalls the camera.
import AVFoundation
import CoreVideo
import Metal

final class FilteredTakeRecorder {
    private let engine: EngineStore
    private let writer: AVAssetWriter
    private let videoIn: AVAssetWriterInput
    private let audioIn: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var textureCache: CVMetalTextureCache?
    private var sessionStarted = false
    private let lock = NSLock()
    private var finished = false
    let width: Int, height: Int

    init?(engine: EngineStore, url: URL, width: Int = 720, height: Int = 1280) {
        self.engine = engine
        self.width = width; self.height = height
        try? FileManager.default.removeItem(at: url)
        guard let w = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return nil }
        writer = w
        videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
        ])
        videoIn.expectsMediaDataInRealTime = true
        audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1, AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 96_000,
        ])
        audioIn.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoIn,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ])
        guard writer.canAdd(videoIn), writer.canAdd(audioIn) else { return nil }
        writer.add(videoIn); writer.add(audioIn)
        guard writer.startWriting() else { return nil }
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, engine.device, nil, &textureCache)
    }

    /// Render the engine's current frame (camera + live FX) and encode it at
    /// `pts`. Main queue (the render thread). Drops when the encoder is busy.
    func appendRenderedFrame(at pts: CMTime) {
        lock.lock(); let done = finished; lock.unlock()
        guard !done, writer.status == .writing, videoIn.isReadyForMoreMediaData,
              let pool = adaptor.pixelBufferPool, let cache = textureCache else { return }
        var pb: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb) == kCVReturnSuccess,
              let pixelBuffer = pb else { return }
        var cvTex: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(
                  kCFAllocatorDefault, cache, pixelBuffer, nil,
                  .bgra8Unorm, width, height, 0, &cvTex) == kCVReturnSuccess,
              let cv = cvTex, let tex = CVMetalTextureGetTexture(cv) else { return }
        engine.render(into: tex)
        engine.renderWait()               // frame must be complete before encode
        if !sessionStarted {
            writer.startSession(atSourceTime: pts)
            sessionStarted = true
        }
        adaptor.append(pixelBuffer, withPresentationTime: pts)
    }

    /// Audio passthrough from the capture delegate (any queue). Audio before
    /// the first video frame is dropped so sound never leads a black frame.
    func appendAudio(_ sb: CMSampleBuffer) {
        lock.lock(); let done = finished; lock.unlock()
        guard !done, sessionStarted, writer.status == .writing,
              audioIn.isReadyForMoreMediaData else { return }
        audioIn.append(sb)
    }

    /// Finish the file; completion on main with the URL (nil on failure).
    func finish(completion: @escaping (URL?) -> Void) {
        lock.lock()
        if finished { lock.unlock(); return completion(nil) }
        finished = true
        lock.unlock()
        videoIn.markAsFinished()
        audioIn.markAsFinished()
        let w = writer
        w.finishWriting {
            let ok = w.status == .completed
            DispatchQueue.main.async { completion(ok ? w.outputURL : nil) }
        }
    }
}
