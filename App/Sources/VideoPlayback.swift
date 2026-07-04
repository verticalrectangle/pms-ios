// VideoPlayback.swift — decode an imported video and feed its frames to the
// engine's Metal compositor (the same submit-frame path as the live camera).
// The AVPlayer is the master clock: a periodic time observer drives the
// transport (onTick), and a CADisplayLink pulls the current frame each vsync.
import AVFoundation
import QuartzCore
import UIKit

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
    private weak var engine: EngineStore?
    private(set) var duration: Double = 0

    /// (currentTime, isPlaying) — the AVPlayer clock, for the transport.
    var onTick: ((Double, Bool) -> Void)?

    struct Segment { let url: URL; let sourceStart: Double; let duration: Double }

    init(engine: EngineStore) {
        self.engine = engine
        // Route audio to the speaker even on silent mode.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        // AVPlayer clock → the transport (~30 Hz). Added once; survives reloads.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            guard let self else { return }
            self.onTick?(time.seconds, self.player.rate > 0)
        }
        startLink()
    }

    /// (Re)build the playable timeline from the ordered clip segments — every
    /// edit (trim/split/delete) calls this. Preserves the play position.
    func load(segments: [Segment]) async {
        let wasPlaying = player.rate > 0
        let at = player.currentTime()

        let comp = AVMutableComposition()
        let vTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let aTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var cursor = CMTime.zero
        for seg in segments {
            let asset = AVURLAsset(url: seg.url)
            let range = CMTimeRange(start: CMTime(seconds: seg.sourceStart, preferredTimescale: 600),
                                    duration: CMTime(seconds: seg.duration, preferredTimescale: 600))
            if let sv = try? await asset.loadTracks(withMediaType: .video).first {
                try? vTrack?.insertTimeRange(range, of: sv, at: cursor)
            }
            if let sa = try? await asset.loadTracks(withMediaType: .audio).first {
                try? aTrack?.insertTimeRange(range, of: sa, at: cursor)
            }
            cursor = CMTimeAdd(cursor, range.duration)
        }
        duration = cursor.seconds

        let item = AVPlayerItem(asset: comp)
        if let vc = try? await AVMutableVideoComposition.videoComposition(withPropertiesOf: comp) {
            item.videoComposition = vc   // bake in orientation
        }
        let out = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(out)
        output = out
        player.replaceCurrentItem(with: item)
        if at.seconds > 0 {
            player.seek(to: CMTimeMinimum(at, CMTime(seconds: duration, preferredTimescale: 600)),
                        toleranceBefore: .zero, toleranceAfter: .zero) { _ in }
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
