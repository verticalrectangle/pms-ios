//  LayerFeeder.swift
//  Feeds the engine's scene compositor (TRACK_LAYERING_PLAN.md stage 2): for
//  every visual layer the projection shows, submit a BGRA frame addressed by
//  engine (track, clip). The engine stacks them bottom-track-first — Swift
//  never decides z-order, only decodes.
//
//    - PRIMARY video track (bottom-most video lane): frames come from the main
//      AVPlayer (the transport master clock) — routed here by VideoPlayback.
//    - OVERLAY video tracks (up to 2): one muted AVPlayer each, slaved to the
//      transport (rate + drift-corrected seeks), frames pulled per display tick.
//    - TEXT layers: CoreGraphics rasters, submitted once per content change
//      (the engine retains layer frames and windows them by clip span).

import AVFoundation
import CoreVideo
import QuartzCore
import UIKit

@MainActor
final class LayerFeeder {
    private weak var engine: EngineStore?
    private var link: CADisplayLink?

    /// One overlay video layer: a muted player slaved to the transport.
    private final class OverlaySource {
        let address: EngineClipAddress
        let clipStart: Double, clipEnd: Double
        let inPoint: Double, speed: Double
        let player = AVPlayer()
        let output: AVAudioFormat? = nil
        var videoOutput: AVPlayerItemVideoOutput?

        init(url: URL, address: EngineClipAddress,
             clipStart: Double, clipEnd: Double, inPoint: Double, speed: Double) {
            self.address = address
            self.clipStart = clipStart; self.clipEnd = clipEnd
            self.inPoint = inPoint; self.speed = max(0.01, speed)
            let item = AVPlayerItem(url: url)
            let out = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            item.add(out)
            videoOutput = out
            player.isMuted = true   // v1: overlay layers are video-only (audio = primary + audio tracks)
            player.replaceCurrentItem(with: item)
        }

        /// Source time for timeline time t.
        func sourceTime(at t: Double) -> Double { inPoint + (t - clipStart) * speed }
        func isActive(at t: Double) -> Bool { t >= clipStart && t < clipEnd }
    }

    private var overlays: [OverlaySource] = []
    private var textKeys: [EngineClipAddress: String] = [:]   // what raster each address holds
    private var imageLayers: [EngineClipAddress: CVPixelBuffer] = [:]
    private var playing = false
    private var playhead: Double = 0
    private var suspendedForExport = false

    /// Maximum simultaneous overlay video decoders (plan §5; primary is extra).
    static let overlayVideoCap = 2

    init(engine: EngineStore) {
        self.engine = engine
        let l = CADisplayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate(); link = nil
        for o in overlays { o.player.pause(); o.player.replaceCurrentItem(with: nil) }
        overlays.removeAll()
    }

    var suspended: Bool {
        get { suspendedForExport }
        set {
            suspendedForExport = newValue
            link?.isPaused = newValue
            if newValue { for o in overlays { o.player.pause() } }
        }
    }

    // MARK: - Rebuild from the projection

    /// Reconfigure sources after a projection refresh. `primaryEngineTrack` is
    /// the video track the main AVPlayer covers; every OTHER video track's
    /// clips become overlay layers, capped (skips are surfaced, not silent).
    /// `excludingText`: the clip being live-edited draws as a SwiftUI overlay,
    /// so its committed raster is cleared to avoid a double draw.
    func rebuild(tracks: [Track], snapshot: EngineProjectSnapshot,
                 primaryEngineTrack: Int,
                 excludingText: EngineClipAddress? = nil,
                 canvas: CGSize = CGSize(width: 1080, height: 1920),
                 resolveMedia: (String) -> URL?) {
        // Overlay video layers
        for o in overlays { o.player.pause(); o.player.replaceCurrentItem(with: nil) }
        overlays.removeAll()
        var skipped = 0
        var liveImages: Set<EngineClipAddress> = []
        for tr in tracks where tr.kind == .video && tr.engineIndex != primaryEngineTrack {
            for c in tr.clips {
                guard let a = c.address, let url = c.sourceURL else { continue }
                if ImageDecoder.isImageURL(url) {
                    liveImages.insert(a)
                    if imageLayers[a] == nil {
                        if let pb = ImageDecoder.pixelBuffer(from: url) {
                            engine?.submitLayerFrame(track: a.track, clip: a.clip, pb, hostTime: -1)
                            imageLayers[a] = pb
                        } else {
                            engine?.submitLayerFrame(track: a.track, clip: a.clip, nil, hostTime: -1)
                        }
                    }
                    continue
                }
                if overlays.count >= Self.overlayVideoCap { skipped += 1; continue }
                overlays.append(OverlaySource(url: url, address: a,
                                              clipStart: c.start, clipEnd: c.end,
                                              inPoint: c.sourceStart, speed: c.speed))
            }
        }
        if skipped > 0 {
            engine?.lastError = "Layer budget: \(skipped) overlay video clip\(skipped == 1 ? "" : "s") beyond the \(Self.overlayVideoCap)-layer cap aren't rendered."
        }
        // Clear stale image layers
        for (a, _) in imageLayers where !liveImages.contains(a) {
            engine?.submitLayerFrame(track: a.track, clip: a.clip, nil, hostTime: -1)
            imageLayers.removeValue(forKey: a)
        }

        // Text layers: raster + submit once per content change; stale ones clear.
        var live: Set<EngineClipAddress> = []
        for tr in tracks where tr.kind == .lyric {
            for c in tr.clips {
                guard let a = c.address, a != excludingText else { continue }
                live.insert(a)
                // Any placement field change re-rasters (position lives IN the
                // raster — the engine composites it as a full-canvas layer).
                let key = "\(c.label)|\(c.fontSize)|\(c.subPos)|\(c.subPosX)|\(c.subPosY)|\(c.subAnchorH)|\(c.subWrapW)|\(Int(canvas.width))x\(Int(canvas.height))"
                guard textKeys[a] != key else { continue }
                if let pb = Self.rasterText(c, canvas: canvas) {
                    engine?.submitLayerFrame(track: a.track, clip: a.clip, pb,
                                             hostTime: -1)   // static layer: no scene-clock update
                    textKeys[a] = key
                } else {
                    textKeys.removeValue(forKey: a)
                    engine?.submitLayerFrame(track: a.track, clip: a.clip, nil, hostTime: -1)   // static layer: no scene-clock update
                }
            }
        }
        for (a, _) in textKeys where !live.contains(a) {
            engine?.submitLayerFrame(track: a.track, clip: a.clip, nil, hostTime: -1)   // static layer: no scene-clock update
            textKeys.removeValue(forKey: a)
        }
        _ = snapshot
    }

    // MARK: - Transport following

    func transport(playhead t: Double, playing p: Bool) {
        playhead = t
        playing = p
        for o in overlays { sync(o) }
    }

    private func sync(_ o: OverlaySource) {
        guard !suspendedForExport else { return }
        let active = o.isActive(at: playhead)
        let want = active ? o.sourceTime(at: playhead) : o.inPoint
        let cur = o.player.currentTime().seconds
        if playing && active {
            if o.player.rate == 0 { o.player.rate = Float(o.speed) }
            if abs(cur - want) > 0.15 {   // drift correction
                o.player.seek(to: CMTime(seconds: want, preferredTimescale: 600),
                              toleranceBefore: .zero, toleranceAfter: .zero)
            }
        } else {
            if o.player.rate != 0 { o.player.pause() }
            if abs(cur - want) > 0.05 {
                o.player.seek(to: CMTime(seconds: want, preferredTimescale: 600),
                              toleranceBefore: CMTime(seconds: 0.05, preferredTimescale: 600),
                              toleranceAfter: CMTime(seconds: 0.05, preferredTimescale: 600))
            }
        }
    }

    // MARK: - Per-vsync frame pull

    @objc private func tick(_ l: CADisplayLink) {
        guard !suspendedForExport, let engine else { return }
        for o in overlays {
            guard o.isActive(at: playhead), let out = o.videoOutput else { continue }
            let itemTime = out.itemTime(forHostTime: l.targetTimestamp)
            guard out.hasNewPixelBuffer(forItemTime: itemTime),
                  let pb = out.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
            else { continue }
            engine.submitLayerFrame(track: o.address.track, clip: o.address.clip, pb,
                                    hostTime: playhead)
        }
    }

    // MARK: - Text raster

    /// Rasterize a title into a canvas-sized transparent BGRA buffer. Placement
    /// comes from TextLayoutModel (the same fractions the canvas handles show),
    /// so preview handles, the engine layer, and export all agree.
    static func rasterText(_ c: Clip, canvas: CGSize = CGSize(width: 1080, height: 1920)) -> CVPixelBuffer? {
        guard !c.label.isEmpty else { return nil }
        let width = Int(canvas.width), height = Int(canvas.height)
        var pbOut: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
                            &pbOut)
        guard let pb = pbOut else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb),
                                  width: width, height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue |
                                              CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPushContext(ctx)
        // CG origin is bottom-left; flip to draw in UIKit coordinates.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        let lay = TextLayoutModel.layout(c.label, clip: c, in: canvas)
        let para = NSMutableParagraphStyle(); para.alignment = lay.alignment
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: lay.fontSize, weight: .black),
            .foregroundColor: UIColor.white, .paragraphStyle: para,
            .shadow: { let s = NSShadow(); s.shadowColor = UIColor.black.withAlphaComponent(0.55)
                       s.shadowBlurRadius = canvas.width * 0.02; s.shadowOffset = .zero; return s }(),
        ]
        (c.label as NSString).draw(in: lay.rect, withAttributes: attrs)
        UIGraphicsPopContext()
        return pb
    }
}
