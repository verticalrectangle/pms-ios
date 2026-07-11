// VideoPlayback.swift — decode an imported video and feed its frames to the
// engine's Metal compositor (the same submit-frame path as the live camera).
// The AVPlayer is the master clock: a periodic time observer drives the
// transport (onTick), and a CADisplayLink pulls the current frame each vsync.
import AVFoundation
import QuartzCore
import UIKit
import CoreImage
import Photos

extension VideoPlayback {
    /// A filmstrip of `count` evenly-spaced JPEG frames — for the timeline
    /// clip's preview. Frames land in the project's cache dir keyed by source
    /// name + frame index, so re-opens reuse them instead of littering temp.
    static func filmstrip(for url: URL, count: Int, cacheDir: URL? = nil) async -> [URL] {
        let asset = AVURLAsset(url: url)
        let dur = (try? await asset.load(.duration))?.seconds ?? 0
        guard dur > 0, count > 0 else { return [] }
        let dir = cacheDir ?? FileManager.default.temporaryDirectory
        let stem = url.deletingPathExtension().lastPathComponent
        // Cache hit: all frames already on disk.
        let expected = (0..<count).map { dir.appendingPathComponent("\(stem)-fs\($0)of\(count).jpg") }
        if expected.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) { return expected }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 160, height: 160)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.4, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter  = CMTime(seconds: 0.4, preferredTimescale: 600)
        var urls: [URL] = []
        for i in 0..<count {
            let sec = dur * (Double(i) + 0.5) / Double(count)
            guard let cg = try? await gen.image(at: CMTime(seconds: sec, preferredTimescale: 600)).image,
                  let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.6) else { continue }
            let dst = expected[i]
            try? data.write(to: dst)
            urls.append(dst)
        }
        return urls
    }
}

@MainActor
final class VideoPlayback {
    let player = AVPlayer()
    private var output: AVPlayerItemVideoOutput?
    private var link: CADisplayLink?
    private var timeObserver: Any?
    private var suppressTicks = false   // ignore the transient 0 during a reload
    private weak var engine: EngineStore?
    private(set) var duration: Double = 0
    private var segments: [Segment] = []
    private var imageBuffers: [URL: CVPixelBuffer] = [:]
    private var size: CGSize = CGSize(width: 1080, height: 1920)

    /// (currentTime, isPlaying) — the AVPlayer clock, for the transport.
    var onTick: ((Double, Bool) -> Void)?

    struct Segment {
        let url: URL; let start: Double; let sourceStart: Double; let duration: Double
        var speed: Double = 1        // timeline seconds consume `speed` source seconds
        var fadeIn: Double = 0; var fadeOut: Double = 0
        var isImage: Bool { ImageDecoder.isImageURL(url) }
    }

    init(engine: EngineStore) {
        self.engine = engine
        // Route audio to the speaker even on silent mode.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        // AVPlayer clock → the transport (~30 Hz). Added once; survives reloads.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            guard let self, !self.suppressTicks else { return }
            self.onTick?(time.seconds, self.player.rate > 0)
        }
        startLink()
    }

    /// Build the AVComposition (+ orientation video composition) from the clip
    /// segments. Clips sit at their timeline `start`; an empty range fills any
    /// gap (front-trim). Composition == timeline, 1:1. Shared by playback + export.
    enum CompositionError: LocalizedError {
        case insertFailed(String, String)
        var errorDescription: String? {
            switch self {
            case .insertFailed(let file, let why): return "Could not add \(file): \(why)"
            }
        }
    }

    /// `audioOnly`: clips whose SOUND plays but whose pixels are engine layers
    /// (audio-track clips; overlay video audio is a v1 gap per the plan).
    static func buildComposition(_ segments: [Segment], titles: [Clip] = [],
                                 audioOnly: [Segment] = [], size: CGSize = CGSize(width: 1080, height: 1920)) async throws -> (AVMutableComposition, AVMutableVideoComposition?) {
        let comp = AVMutableComposition()
        let vTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let aTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var cursor = CMTime.zero
        var firstVideoTransformSet = false
        for seg in segments.sorted(by: { $0.start < $1.start }) {
            let clipStart = CMTime(seconds: seg.start, preferredTimescale: 600)
            if CMTimeCompare(clipStart, cursor) > 0 {
                let gap = CMTimeRange(start: cursor, duration: CMTimeSubtract(clipStart, cursor))
                vTrack?.insertEmptyTimeRange(gap)
                aTrack?.insertEmptyTimeRange(gap)
            }
            let speed = max(0.01, seg.speed)
            let srcRange = CMTimeRange(start: CMTime(seconds: seg.sourceStart, preferredTimescale: 600),
                                       duration: CMTime(seconds: seg.duration * speed, preferredTimescale: 600))
            let tlDuration = CMTime(seconds: seg.duration, preferredTimescale: 600)
            if seg.isImage {
                let imageRange = CMTimeRange(start: clipStart, duration: tlDuration)
                vTrack?.insertEmptyTimeRange(imageRange)
                aTrack?.insertEmptyTimeRange(imageRange)
            } else {
                let asset = AVURLAsset(url: seg.url)
                do {
                    if let sv = try await asset.loadTracks(withMediaType: .video).first {
                        try vTrack?.insertTimeRange(srcRange, of: sv, at: clipStart)
                        // Propagate the source track's orientation transform. AVComposition tracks
                        // do NOT inherit preferredTransform on insert, so portrait phone clips
                        // would render sideways unless we copy it over.
                        if !firstVideoTransformSet {
                            vTrack?.preferredTransform = try await sv.load(.preferredTransform)
                            firstVideoTransformSet = true
                        }
                        if speed != 1 {
                            vTrack?.scaleTimeRange(CMTimeRange(start: clipStart, duration: srcRange.duration),
                                                   toDuration: tlDuration)
                        }
                    }
                    if let sa = try await asset.loadTracks(withMediaType: .audio).first {
                        try aTrack?.insertTimeRange(srcRange, of: sa, at: clipStart)
                        if speed != 1 {
                            aTrack?.scaleTimeRange(CMTimeRange(start: clipStart, duration: srcRange.duration),
                                                   toDuration: tlDuration)
                        }
                    }
                } catch {
                    // Propagate — a silently skipped clip reads as data loss.
                    throw CompositionError.insertFailed(seg.url.lastPathComponent, error.localizedDescription)
                }
            }
            cursor = CMTimeAdd(clipStart, tlDuration)
        }
        // Audio-only segments land on their own composition tracks (created
        // lazily so overlapping sound sources coexist). Failures propagate.
        var extraAudio: [AVMutableCompositionTrack] = []
        for seg in audioOnly.sorted(by: { $0.start < $1.start }) {
            let asset = AVURLAsset(url: seg.url)
            guard let sa = try? await asset.loadTracks(withMediaType: .audio).first else { continue }
            let speed = max(0.01, seg.speed)
            let srcRange = CMTimeRange(start: CMTime(seconds: seg.sourceStart, preferredTimescale: 600),
                                       duration: CMTime(seconds: seg.duration * speed, preferredTimescale: 600))
            let at = CMTime(seconds: seg.start, preferredTimescale: 600)
            var host: AVMutableCompositionTrack?
            for tr in extraAudio where host == nil {
                if (try? tr.insertTimeRange(srcRange, of: sa, at: at)) != nil { host = tr }
            }
            if host == nil, extraAudio.count < 4,
               let tr = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                do { try tr.insertTimeRange(srcRange, of: sa, at: at) }
                catch { throw CompositionError.insertFailed(seg.url.lastPathComponent, error.localizedDescription) }
                extraAudio.append(tr)
                host = tr
            }
            if let host, speed != 1 {
                host.scaleTimeRange(CMTimeRange(start: at, duration: srcRange.duration),
                                    toDuration: CMTime(seconds: seg.duration, preferredTimescale: 600))
            }
        }

        // The UNIFIED composite: fold every layer (video base → fades → titles)
        // through ONE Core Image handler, shared by preview + export, in track
        // order. Only engaged when there's something to composite.
        // ALWAYS composite through the Core Image handler: req.sourceImage is
        // correctly ORIENTED (the auto videoComposition mishandles the phone's
        // rotation transform → sideways), and it's where fades + titles apply.
        // For a plain clip the handler is a pass-through.
        var size = size
        if let v = try? await comp.loadTracks(withMediaType: .video).first,
           let n = try? await v.load(.naturalSize), n.width > 0, n.height > 0,
           let tf = try? await v.load(.preferredTransform) {
            let r = n.applying(tf); size = CGSize(width: abs(r.width), height: abs(r.height))
        }
        let titleLayers: [(clip: Clip, image: CIImage)] = titles.compactMap { c in
            TextRasterizer.image(for: c, size: size).map { (c, $0) }
        }
        let segs = segments
        let vc = AVMutableVideoComposition(asset: comp, applyingCIFiltersWithHandler: { req in
            let t = req.compositionTime.seconds
            let extent = req.sourceImage.extent
            var acc = req.sourceImage                       // BASE = the video track (oriented)
            if let s = segs.first(where: { $0.start <= t && t < $0.start + $0.duration }) {
                let o = fadeOpacity(s, at: t)
                if o < 0.999 {
                    acc = acc.applyingFilter("CIColorMatrix", parameters: [
                        "inputRVector": CIVector(x: o, y: 0, z: 0, w: 0),
                        "inputGVector": CIVector(x: 0, y: o, z: 0, w: 0),
                        "inputBVector": CIVector(x: 0, y: 0, z: o, w: 0),
                        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                    ]).cropped(to: extent)
                }
            }
            for (clip, img) in titleLayers where t >= clip.start && t < clip.end {
                acc = img.composited(over: acc)                 // titles over the video
            }
            req.finish(with: acc.cropped(to: extent), context: nil)
        })
        vc.renderSize = size
        return (comp, vc)
    }

    /// Linear fade-from-black opacity for a segment at composition time `t`.
    static func fadeOpacity(_ s: Segment, at t: Double) -> Double {
        let local = t - s.start
        var o = 1.0
        if s.fadeIn  > 0, local < s.fadeIn            { o = min(o, local / s.fadeIn) }
        if s.fadeOut > 0, local > s.duration - s.fadeOut { o = min(o, (s.duration - local) / s.fadeOut) }
        return max(0, min(1, o))
    }

    private var loadGeneration = 0

    /// (Re)build the playable timeline from the ordered clip segments — every
    /// edit (trim/split/delete) calls this. Preserves the play position.
    /// Rapid edits cancel each other: only the newest rebuild installs.
    func load(segments: [Segment], titles: [Clip] = [], audioOnly: [Segment] = [],
              seekTo: Double? = nil, size: CGSize = CGSize(width: 1080, height: 1920)) async {
        loadGeneration += 1
        let gen = loadGeneration
        let wasPlaying = player.rate > 0
        let at = seekTo.map { CMTime(seconds: $0, preferredTimescale: 600) } ?? player.currentTime()
        suppressTicks = true   // swallow the item-swap's transient 0 until the seek lands
        self.size = size
        imageBuffers.removeAll()
        self.segments = segments

        let comp: AVMutableComposition
        let vc: AVMutableVideoComposition?
        do {
            (comp, vc) = try await Self.buildComposition(segments, titles: titles, audioOnly: audioOnly, size: size)
        } catch {
            engine?.lastError = error.localizedDescription
            suppressTicks = false
            return
        }
        guard gen == loadGeneration else { return }   // a newer edit superseded this rebuild
        duration = comp.duration.seconds

        let item = AVPlayerItem(asset: comp)
        item.videoComposition = vc   // bake in orientation
        let out = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(out)
        output = out
        player.replaceCurrentItem(with: item)
        if seekTo != nil || at.seconds > 0 {
            player.seek(to: CMTimeMinimum(at, CMTime(seconds: duration, preferredTimescale: 600)),
                        toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                self?.suppressTicks = false   // resume ticking only once we're back at `at`
                self?.pushFrame()
            }
        } else {
            suppressTicks = false
        }
        if wasPlaying { player.play() }
        pushFrame()
    }

    func play()  { player.play() }
    func pause() { player.pause() }

    func seek(_ t: Double) {
        // A small tolerance keeps scrubbing responsive (exact-frame seeks are
        // slow); AVPlayer coalesces rapid in-flight seeks.
        let tol = CMTime(seconds: 0.08, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600),
                    toleranceBefore: tol, toleranceAfter: tol) { [weak self] _ in
            self?.pushFrame()
        }
    }

    func stop() {
        link?.invalidate(); link = nil
        if let o = timeObserver { player.removeTimeObserver(o); timeObserver = nil }
        player.pause()
        player.replaceCurrentItem(with: nil)
        engine?.clearContent()
    }

    private func startLink() {
        link?.invalidate()
        let l = CADisplayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick(_ l: CADisplayLink) { pushFrame(hostTime: l.targetTimestamp) }

    var suspended = false   // export takes exclusive engine access (no live frames)

    /// When set, decoded frames route here (the layer feeder addresses them to
    /// the engine's scene compositor) instead of the legacy single-content path.
    var frameSink: ((CVPixelBuffer, Double) -> Void)?

    private func pushFrame(hostTime: CFTimeInterval = CACurrentMediaTime()) {
        guard !suspended, let out = output else { return }
        let itemTime = out.itemTime(forHostTime: hostTime)
        let t = itemTime.seconds
        if let s = imageSegmentAt(t) {
            guard let pb = imagePixelBuffer(for: s.url) else { return }
            if let frameSink { frameSink(pb, t) }
            else { engine?.submitCameraFrame(pb, rotation: 0, hostTime: t) }
            return
        }
        guard out.hasNewPixelBuffer(forItemTime: itemTime),
              let pb = out.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
        else { return }
        if let frameSink { frameSink(pb, t) }
        else { engine?.submitCameraFrame(pb, rotation: 0, hostTime: t) }
    }
    private func imageSegmentAt(_ t: Double) -> Segment? {
        segments.first(where: { $0.isImage && t >= $0.start && t < $0.start + $0.duration })
    }
    private func imagePixelBuffer(for url: URL) -> CVPixelBuffer? {
        if let cached = imageBuffers[url] { return cached }
        guard let pb = ImageDecoder.pixelBuffer(from: url) else { return nil }
        imageBuffers[url] = pb
        return pb
    }
}

// MARK: - Text as a composite layer

/// Rasterizes a title clip into a full-frame CIImage (transparent elsewhere) so
/// it composites in the layer fold — identical in preview and export. Cached
/// (static per clip); built on the main actor by buildComposition.
@MainActor
enum TextRasterizer {
    private static var cache: [String: CIImage] = [:]

    static func image(for clip: Clip, size: CGSize) -> CIImage? {
        guard !clip.label.isEmpty, size.width > 1 else { return nil }
        // Key on CONTENT + every style input of the raster (currently text +
        // frame size; extend when per-clip fonts/colors land). Never the clip
        // id — projection ids change every refresh and would bloat the cache.
        let key = "\(clip.label)|\(Int(size.width))x\(Int(size.height))"
        if let c = cache[key] { return c }
        if cache.count > 128 { cache.removeAll() }   // crude bound; rebuilt on demand
        let root = CALayer(); root.frame = CGRect(origin: .zero, size: size)
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let text = CATextLayer()
        text.contentsScale = 3; text.isWrapped = true; text.alignmentMode = .center
        text.string = NSAttributedString(string: clip.label, attributes: [
            .font: UIFont.systemFont(ofSize: size.width * 0.12, weight: .black),
            .foregroundColor: UIColor.white, .paragraphStyle: para,
            .shadow: { let s = NSShadow(); s.shadowColor = UIColor.black.withAlphaComponent(0.55)
                       s.shadowBlurRadius = size.width * 0.02; s.shadowOffset = .zero; return s }(),
        ])
        let h = size.height * 0.25
        text.frame = CGRect(x: size.width * 0.06, y: (size.height - h) / 2, width: size.width * 0.88, height: h)
        root.addSublayer(text)
        // scale 1 → the image is exactly `size` px, matching the video frame
        // (default screen-scale would make it 3× and crop the text out of view).
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = false
        let cg = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in root.render(in: ctx.cgContext) }.cgImage
        guard let cg else { return nil }
        let img = CIImage(cgImage: cg)
        cache[key] = img
        return img
    }
    static func invalidate() { cache.removeAll() }
}

// MARK: - Export

/// Renders the timeline's AVComposition to an .mp4 the user can save or share.
@MainActor
enum VideoExporter {
    /// Returns the written file URL, or nil on failure. `progress` is 0…1.
    /// Titles fold into the SAME Core Image handler as fades (buildComposition),
    /// so preview and export are pixel-identical — no separate animationTool.
    /// Export baking the engine's GPU FX in: read the composited frames (orientation
    /// + fades + titles via the CI handler), run EACH through the engine FX runner
    /// (same as preview → preview == export), and encode. `engine` must have
    /// exclusive access — the caller suspends the live preview. Ported from the
    /// verified macOS harness.
    enum ExportError: LocalizedError {
        case emptyTimeline
        case setup(String)
        case cancelled
        case failed(String)
        var errorDescription: String? {
            switch self {
            case .emptyTimeline:   return "Nothing to export — the timeline is empty."
            case .setup(let d):    return "Export setup failed: \(d)"
            case .cancelled:       return "Export cancelled."
            case .failed(let d):   return "Export failed: \(d)"
            }
        }
    }

    /// One overlay video layer for export: its own reader stepped to the
    /// output frame clock (same submissions as preview → same engine scene).
    struct OverlayLayer {
        let track: Int, clip: Int
        let url: URL
        let start: Double, end: Double, inPoint: Double, speed: Double
    }
    struct TextLayer { let track: Int, clip: Int; let clipModel: Clip }
    /// (start, end, track, clip) spans of the primary track's clips — resolves
    /// which engine address each base frame belongs to.
    typealias BaseSpan = (start: Double, end: Double, track: Int, clip: Int)

    nonisolated static func export(_ segments: [VideoPlayback.Segment],
                                   audioOnly: [VideoPlayback.Segment] = [],
                                   overlays: [OverlayLayer] = [],
                                   texts: [TextLayer] = [],
                                   baseSpans: [BaseSpan] = [],
                                   engine: EngineStore, size: (w: Int, h: Int),
                                   isCancelled: @escaping () -> Bool = { false },
                                   progress: @escaping (Double) -> Void) async throws -> URL {
        let (comp, vc0) = try await VideoPlayback.buildComposition(segments, audioOnly: audioOnly, size: CGSize(width: size.w, height: size.h))

        // Static text and image layers: submit once; the engine windows them by clip span.
        // Images are decoded to their natural pixel size and the engine scales them.
        let canvasSize = CGSize(width: size.w, height: size.h)
        for t in texts {
            let pb = await LayerFeeder.rasterText(t.clipModel, canvas: canvasSize)
            engine.submitLayerFrame(track: t.track, clip: t.clip, pb, hostTime: -1)
        }
        var imageBaseClips = Set<Int>()
        for seg in segments where ImageDecoder.isImageURL(seg.url) {
            if let span = baseSpans.first(where: { $0.start == seg.start && $0.end == seg.start + seg.duration }) {
                guard let pb = ImageDecoder.pixelBuffer(from: seg.url) else { continue }
                engine.submitLayerFrame(track: span.track, clip: span.clip, pb, hostTime: -1)
                imageBaseClips.insert(span.clip)
            }
        }
        var overlayReaders: [OverlayFrameSource] = []
        for o in overlays {
            if ImageDecoder.isImageURL(o.url) {
                guard let pb = ImageDecoder.pixelBuffer(from: o.url) else { continue }
                engine.submitLayerFrame(track: o.track, clip: o.clip, pb, hostTime: -1)
            } else {
                overlayReaders.append(try await OverlayFrameSource(o))
            }
        }
        let ovl = overlayReaders
        let duration = comp.duration.seconds
        guard duration > 0 else { throw ExportError.emptyTimeline }
        guard let vc = vc0,
              let vtracks = try? await comp.loadTracks(withMediaType: .video), !vtracks.isEmpty else {
            throw ExportError.setup("no video tracks in the composition")
        }
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: comp) }
        catch { throw ExportError.setup("AVAssetReader: \(error.localizedDescription)") }
        let W = size.w, H = size.h
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("PopMaker_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: out)

        let rout = AVAssetReaderVideoCompositionOutput(videoTracks: vtracks, videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        rout.videoComposition = vc
        guard reader.canAdd(rout) else { throw ExportError.setup("reader rejected video output") }
        reader.add(rout)

        // Audio: pass the composition's audio through (decode to LPCM here, re-encode
        // AAC on the writer) so exports carry sound — the FX bake is video-only.
        let atracks = (try? await comp.loadTracks(withMediaType: .audio)) ?? []
        var aout: AVAssetReaderAudioMixOutput?
        if !atracks.isEmpty {
            let a = AVAssetReaderAudioMixOutput(audioTracks: atracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false])
            if reader.canAdd(a) { reader.add(a); aout = a }
        }

        let writer: AVAssetWriter
        do { writer = try AVAssetWriter(outputURL: out, fileType: .mp4) }
        catch { throw ExportError.setup("AVAssetWriter: \(error.localizedDescription)") }
        let bitrate = min(W * H * 8, 24_000_000)   // ~HighestQuality; was an unset (low) default
        let win = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
            AVVideoColorPropertiesKey: [      // tag Rec.709 SDR (players were guessing)
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]])
        win.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: win, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H,
            kCVPixelBufferMetalCompatibilityKey as String: true])
        guard writer.canAdd(win) else { throw ExportError.setup("writer rejected video input") }
        writer.add(win)
        var ain: AVAssetWriterInput?
        if aout != nil {
            let a = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 48000, AVEncoderBitRateKey: 160_000])
            a.expectsMediaDataInRealTime = false
            if writer.canAdd(a) { writer.add(a); ain = a }
        }
        guard reader.startReading() else {
            throw ExportError.setup("reader: \(reader.error?.localizedDescription ?? "could not start")")
        }
        guard writer.startWriting() else {
            throw ExportError.setup("writer: \(writer.error?.localizedDescription ?? "could not start")")
        }
        writer.startSession(atSourceTime: .zero)

        var cacheOut: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, engine.device, nil, &cacheOut)
        guard let cache = cacheOut, let pool = adaptor.pixelBufferPool else {
            throw ExportError.setup("no Metal texture cache / pixel buffer pool")
        }

        let result = await withCheckedContinuation { (cont: CheckedContinuation<Result<URL, ExportError>, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var pendingAudio: CMSampleBuffer?      // pulled-but-not-yet-due (PTS-gated drain)
                var audioDone = (aout == nil)
                // Append audio whose PTS <= t so both reader outputs advance together —
                // bounds reader buffering to ~one frame of lookahead. Without this the AAC
                // encoder stays ready and pulls the whole song on frame 0 → the reader
                // buffers the entire timeline → jetsam on long exports.
                func drainAudio(upTo t: Double) {
                    guard let ain, let aout, !audioDone else { return }
                    while ain.isReadyForMoreMediaData {
                        guard let asb = pendingAudio ?? aout.copyNextSampleBuffer() else { audioDone = true; return }
                        pendingAudio = nil
                        if CMSampleBufferGetPresentationTimeStamp(asb).seconds <= t { ain.append(asb) }
                        else { pendingAudio = asb; return }      // not due yet — hold for a later frame
                    }
                }
                var cancelled = false
                while reader.status == .reading, writer.status == .writing,
                      let sb = rout.copyNextSampleBuffer() {
                    if isCancelled() { cancelled = true; break }
                    guard let ipb = CMSampleBufferGetImageBuffer(sb) else { continue }
                    let pt = CMSampleBufferGetPresentationTimeStamp(sb)
                    let t = pt.seconds
                    if let span = baseSpans.first(where: { t >= $0.start && t < $0.end }) ?? baseSpans.last {
                        if imageBaseClips.contains(span.clip) {
                            // image base is a static layer; the composition frame is empty
                        } else {
                            engine.submitLayerFrame(track: span.track, clip: span.clip, ipb, hostTime: t)
                        }
                    } else {
                        // ...no layered project → legacy single-content path.
                        engine.submitCameraFrame(ipb, rotation: 0, hostTime: t)
                    }
                    for r in ovl { r.submit(at: t, engine: engine) }   // overlay layers at this frame time
                    var opb: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &opb)
                    var ctex: CVMetalTexture?
                    if let opb {
                        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, opb, nil,
                                                                  .bgra8Unorm, W, H, 0, &ctex)
                    }
                    guard let opb, let ctex, let otex = CVMetalTextureGetTexture(ctex) else { continue }
                    engine.render(into: otex)        // engine FX chain, windowed to the frame time
                    engine.renderWait()
                    while !win.isReadyForMoreMediaData, writer.status == .writing { usleep(4000) }  // status escape → no wedge on disk-full
                    adaptor.append(opb, withPresentationTime: pt)
                    drainAudio(upTo: pt.seconds)
                    let p = min(0.99, pt.seconds / duration)
                    DispatchQueue.main.async { progress(p) }
                }
                if let ain, let aout {               // flush the audio tail
                    if let p = pendingAudio, writer.status == .writing { ain.append(p) }
                    pendingAudio = nil
                    while !audioDone, writer.status == .writing, let asb = aout.copyNextSampleBuffer() {
                        while !ain.isReadyForMoreMediaData, writer.status == .writing { usleep(2000) }
                        ain.append(asb)
                    }
                }
                // Reader/writer failure (e.g. disk full) → cancel, never hand back a truncated file as success.
                let ok = !cancelled && reader.status != .failed && writer.status == .writing
                if ok {
                    ain?.markAsFinished(); win.markAsFinished()
                    writer.finishWriting {
                        DispatchQueue.main.async { progress(1) }
                        if writer.status == .completed {
                            cont.resume(returning: .success(out))
                        } else {
                            cont.resume(returning: .failure(.failed(
                                writer.error?.localizedDescription ?? "writer did not complete")))
                        }
                    }
                } else {
                    let detail = cancelled ? nil
                        : reader.error?.localizedDescription ?? writer.error?.localizedDescription
                    reader.cancelReading()
                    writer.cancelWriting()
                    try? FileManager.default.removeItem(at: out)
                    DispatchQueue.main.async { progress(1) }
                    cont.resume(returning: cancelled ? .failure(.cancelled)
                                                     : .failure(.failed(detail ?? "reader/writer failed")))
                }
            }
        }
        return try result.get()
    }

    /// Save a finished export into the Photos library (add-only permission).
    static func saveToPhotos(_ url: URL) async -> Bool {
        let status = await withCheckedContinuation { (c: CheckedContinuation<PHAuthorizationStatus, Never>) in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { c.resume(returning: $0) }
        }
        guard status == .authorized || status == .limited else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            return true
        } catch { return false }
    }
}

// MARK: - Export overlay source (off-main: lives outside the @MainActor exporter)

/// Sequential frame source for one overlay clip during export: an
/// AVAssetReader over the clip's source range, stepped monotonically to each
/// output frame's time. Latest frame at-or-before the target wins. Driven
/// from the export worker queue.
final class OverlayFrameSource {
    private let layer: VideoExporter.OverlayLayer
    private let reader: AVAssetReader
    private let out: AVAssetReaderTrackOutput
    private var current: CVPixelBuffer?
    private var pending: (pts: Double, pb: CVPixelBuffer)?
    private var wasActive = false

    init(_ layer: VideoExporter.OverlayLayer) async throws {
        self.layer = layer
        let asset = AVURLAsset(url: layer.url)
        guard let vt = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoExporter.ExportError.setup("overlay \(layer.url.lastPathComponent): no video track")
        }
        reader = try AVAssetReader(asset: asset)
        out = AVAssetReaderTrackOutput(track: vt, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        guard reader.canAdd(out) else {
            throw VideoExporter.ExportError.setup("overlay \(layer.url.lastPathComponent): reader rejected output")
        }
        reader.add(out)
        let speed = max(0.01, layer.speed)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: layer.inPoint, preferredTimescale: 600),
            duration: CMTime(seconds: (layer.end - layer.start) * speed, preferredTimescale: 600))
        guard reader.startReading() else {
            throw VideoExporter.ExportError.setup("overlay \(layer.url.lastPathComponent): \(reader.error?.localizedDescription ?? "reader start failed")")
        }
    }

    /// Advance to output time t and submit the layer frame (clears the layer
    /// when t leaves the clip's span).
    func submit(at t: Double, engine: EngineStore) {
        let active = t >= layer.start && t < layer.end
        if !active {
            if wasActive {
                engine.submitLayerFrame(track: layer.track, clip: layer.clip, nil, hostTime: t)
                wasActive = false
            }
            return
        }
        let target = layer.inPoint + (t - layer.start) * max(0.01, layer.speed)
        while true {
            if let p = pending {
                if p.pts <= target { current = p.pb; pending = nil }
                else { break }   // next frame is in the future — keep current
            }
            guard pending == nil, reader.status == .reading,
                  let sb = out.copyNextSampleBuffer() else { break }
            guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(sb).seconds
            if pts <= target { current = pb }
            else { pending = (pts, pb) }
        }
        if let current {
            engine.submitLayerFrame(track: layer.track, clip: layer.clip, current, hostTime: t)
            wasActive = true
        }
    }
}
