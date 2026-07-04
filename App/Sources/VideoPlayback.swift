// VideoPlayback.swift — decode an imported video and feed its frames to the
// engine's Metal compositor (the same submit-frame path as the live camera).
// The AVPlayer is the master clock: a periodic time observer drives the
// transport (onTick), and a CADisplayLink pulls the current frame each vsync.
import AVFoundation
import QuartzCore
import UIKit
import CoreImage

extension VideoPlayback {
    /// A filmstrip of `count` evenly-spaced JPEG frames written to temp files —
    /// for the timeline clip's preview. A coarse tolerance keeps it fast.
    static func filmstrip(for url: URL, count: Int) async -> [URL] {
        let asset = AVURLAsset(url: url)
        let dur = (try? await asset.load(.duration))?.seconds ?? 0
        guard dur > 0, count > 0 else { return [] }
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
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
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

    /// (currentTime, isPlaying) — the AVPlayer clock, for the transport.
    var onTick: ((Double, Bool) -> Void)?

    struct Segment {
        let url: URL; let start: Double; let sourceStart: Double; let duration: Double
        var fadeIn: Double = 0; var fadeOut: Double = 0
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
    static func buildComposition(_ segments: [Segment]) async -> (AVMutableComposition, AVMutableVideoComposition?) {
        let comp = AVMutableComposition()
        let vTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let aTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var cursor = CMTime.zero
        for seg in segments.sorted(by: { $0.start < $1.start }) {
            let clipStart = CMTime(seconds: seg.start, preferredTimescale: 600)
            if CMTimeCompare(clipStart, cursor) > 0 {
                let gap = CMTimeRange(start: cursor, duration: CMTimeSubtract(clipStart, cursor))
                vTrack?.insertEmptyTimeRange(gap)
                aTrack?.insertEmptyTimeRange(gap)
            }
            let asset = AVURLAsset(url: seg.url)
            let range = CMTimeRange(start: CMTime(seconds: seg.sourceStart, preferredTimescale: 600),
                                    duration: CMTime(seconds: seg.duration, preferredTimescale: 600))
            if let sv = try? await asset.loadTracks(withMediaType: .video).first {
                try? vTrack?.insertTimeRange(range, of: sv, at: clipStart)
            }
            if let sa = try? await asset.loadTracks(withMediaType: .audio).first {
                try? aTrack?.insertTimeRange(range, of: sa, at: clipStart)
            }
            cursor = CMTimeAdd(clipStart, range.duration)
        }
        // If any clip fades, apply it per-frame via Core Image (handles orientation,
        // works in preview + export). Otherwise the plain orientation composition.
        if segments.contains(where: { $0.fadeIn > 0 || $0.fadeOut > 0 }) {
            let segs = segments
            let vc = AVMutableVideoComposition(asset: comp, applyingCIFiltersWithHandler: { req in
                let t = req.compositionTime.seconds
                var img = req.sourceImage
                if let s = segs.first(where: { $0.start <= t && t < $0.start + $0.duration }) {
                    let o = fadeOpacity(s, at: t)
                    if o < 0.999 {
                        img = img.applyingFilter("CIColorMatrix", parameters: [
                            "inputRVector": CIVector(x: o, y: 0, z: 0, w: 0),
                            "inputGVector": CIVector(x: 0, y: o, z: 0, w: 0),
                            "inputBVector": CIVector(x: 0, y: 0, z: o, w: 0),
                            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                        ]).cropped(to: req.sourceImage.extent)
                    }
                }
                req.finish(with: img, context: nil)
            })
            return (comp, vc)
        }
        let vc = try? await AVMutableVideoComposition.videoComposition(withPropertiesOf: comp)
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

    /// (Re)build the playable timeline from the ordered clip segments — every
    /// edit (trim/split/delete) calls this. Preserves the play position.
    func load(segments: [Segment], seekTo: Double? = nil) async {
        let wasPlaying = player.rate > 0
        let at = seekTo.map { CMTime(seconds: $0, preferredTimescale: 600) } ?? player.currentTime()
        suppressTicks = true   // swallow the item-swap's transient 0 until the seek lands

        let (comp, vc) = await Self.buildComposition(segments)
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

    private func pushFrame(hostTime: CFTimeInterval = CACurrentMediaTime()) {
        guard let out = output else { return }
        let itemTime = out.itemTime(forHostTime: hostTime)
        guard out.hasNewPixelBuffer(forItemTime: itemTime),
              let pb = out.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
        else { return }
        engine?.submitCameraFrame(pb, rotation: 0, hostTime: itemTime.seconds)
    }
}

// MARK: - Export

/// Renders the timeline's AVComposition to an .mp4 the user can save or share.
@MainActor
enum VideoExporter {
    /// Returns the written file URL, or nil on failure. `progress` is 0…1.
    /// `titles` are the text/lyric clips to bake in (via a Core Animation overlay).
    static func export(_ segments: [VideoPlayback.Segment], titles: [Clip] = [],
                       progress: @escaping (Double) -> Void) async -> URL? {
        let (comp, vc) = await VideoPlayback.buildComposition(segments)
        guard comp.duration.seconds > 0,
              let session = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality)
        else { return nil }

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("PopMaker_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: out)
        session.outputURL = out
        session.outputFileType = .mp4
        if let vc {
            if !titles.isEmpty { bakeTitles(into: vc, clips: titles, total: comp.duration.seconds) }
            session.videoComposition = vc
        }

        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            progress(Double(session.progress))
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { c.resume() }
        }
        timer.invalidate()
        progress(1)
        return session.status == .completed ? out : nil
    }

    /// Bake the title clips as a Core Animation overlay, timed to each clip's span.
    /// Matches the SwiftUI preview: bold, white, centered, ~12% of the width.
    private static func bakeTitles(into vc: AVMutableVideoComposition, clips: [Clip], total: Double) {
        let size = vc.renderSize
        guard size.width > 0, total > 0 else { return }
        let parent = CALayer(); parent.frame = CGRect(origin: .zero, size: size)
        let videoLayer = CALayer(); videoLayer.frame = parent.frame
        parent.addSublayer(videoLayer)

        let para = NSMutableParagraphStyle(); para.alignment = .center
        for clip in clips where !clip.label.isEmpty {
            let t = CATextLayer()
            t.contentsScale = 3
            t.isWrapped = true
            t.alignmentMode = .center
            t.string = NSAttributedString(string: clip.label, attributes: [
                .font: UIFont.systemFont(ofSize: size.width * 0.12, weight: .black),
                .foregroundColor: UIColor.white,
                .paragraphStyle: para,
                .shadow: { let s = NSShadow(); s.shadowColor = UIColor.black.withAlphaComponent(0.55)
                           s.shadowBlurRadius = size.width * 0.02; return s }(),
            ])
            let h = size.height * 0.25
            t.frame = CGRect(x: size.width * 0.06, y: (size.height - h) / 2, width: size.width * 0.88, height: h)

            // opacity ON only during [start, end] (discrete keyframes over the whole clip)
            let s = min(max(clip.start / total, 0), 1), e = min(max(clip.end / total, 0), 1)
            let anim = CAKeyframeAnimation(keyPath: "opacity")
            anim.calculationMode = .discrete
            anim.duration = total
            anim.beginTime = AVCoreAnimationBeginTimeAtZero
            anim.isRemovedOnCompletion = false
            anim.fillMode = .forwards
            if s <= 0.001 { anim.keyTimes = [0, NSNumber(value: e)]; anim.values = [1, 0] }
            else          { anim.keyTimes = [0, NSNumber(value: s), NSNumber(value: e)]; anim.values = [0, 1, 0] }
            t.opacity = 0
            t.add(anim, forKey: "vis")
            parent.addSublayer(t)
        }
        vc.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)
    }
}
