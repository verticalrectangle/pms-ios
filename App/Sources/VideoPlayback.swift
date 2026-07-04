// VideoPlayback.swift — decode an imported video and feed its frames to the
// engine's Metal compositor (the same submit-frame path as the live camera).
// AVPlayer is the clock; a CADisplayLink pulls the current frame each vsync and
// pushes it to the canvas. play/pause/seek drive the player.
import AVFoundation
import QuartzCore

@MainActor
final class VideoPlayback {
    let player = AVPlayer()
    private var output: AVPlayerItemVideoOutput?
    private var link: CADisplayLink?
    private weak var engine: EngineStore?
    private(set) var duration: Double = 0

    init(engine: EngineStore) { self.engine = engine }

    /// Load a video URL. Applies the source orientation transform so frames come
    /// out upright, then starts pumping frames to the canvas.
    func load(url: URL) async {
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
        startLink()
        pushFrame()   // show the first frame immediately (paused)
    }

    func play()  { player.play() }
    func pause() { player.pause() }
    func seek(_ t: Double) {
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.pushFrame()   // update the still while scrubbing
        }
    }

    func stop() {
        link?.invalidate(); link = nil
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
