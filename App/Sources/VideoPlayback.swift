// VideoPlayback.swift — decode an imported video and feed its frames to the
// engine's Metal compositor (the same submit-frame path as the live camera).
// The AVPlayer is the master clock: a periodic time observer drives the
// transport (onTick), and a CADisplayLink pulls the current frame each vsync.
import AVFoundation
import QuartzCore

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

    init(engine: EngineStore) { self.engine = engine }

    func load(url: URL) async {
        // Route audio to the speaker even on silent mode.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        if let comp = try? await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset) {
            item.videoComposition = comp   // bake in the display orientation
        }
        let out = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(out)
        output = out
        player.replaceCurrentItem(with: item)
        duration = (try? await asset.load(.duration))?.seconds ?? 0

        // The AVPlayer clock → the transport (~30 Hz).
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            guard let self else { return }
            self.onTick?(time.seconds, self.player.rate > 0)
        }
        startLink()
        pushFrame()   // first frame (paused)
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
