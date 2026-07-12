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
import CoreText
import QuartzCore
import SwiftUI
import UIKit

/// Loads bundled custom display fonts (.ttf in App/Resources/Fonts) and
/// resolves them by the same sanitized name the desktop engine uses.
enum DisplayFonts {
    private static var registered = false
    private static var loaded: [String: String] = [:]   // sanitized name → PostScript name

    static func registerAll() {
        guard !registered else { return }
        guard let fontsURL = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") else { return }
        for url in fontsURL {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            let base = url.deletingPathExtension().lastPathComponent
            let sanitized = base.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "_", options: .regularExpression)
            // After registration, get the PostScript name via CGFont.
            if let data = try? Data(contentsOf: url),
               let provider = CGDataProvider(data: data as CFData),
               let cgFont = CGFont(provider) {
                if let ps = cgFont.postScriptName as String? { loaded[sanitized] = ps }
            }
        }
    }

    /// Returns a UIFont for the given engine font id (e.g. "scratchl"),
    /// falling back to system black weight if not found.
    static func font(_ id: String, size: CGFloat, weight: UIFont.Weight = .black) -> UIFont {
        registerAll()
        if let ps = loaded[id], let f = UIFont(name: ps, size: size) { return f }
        return UIFont.systemFont(ofSize: size, weight: weight)
    }
    /// Returns the PostScript name for SwiftUI's .font(.custom(...)) or nil
    /// if the font isn't loaded (caller should fall back to system).
    static func postScriptName(_ id: String) -> String? {
        registerAll()
        return loaded[id]
    }
    /// Returns a SwiftUI Font for the given engine font id, falling back
    /// to system black weight.
    static func swiftUIFont(_ id: String, size: CGFloat) -> Font {
        registerAll()
        if let ps = loaded[id] { return .custom(ps, size: size) }
        return .system(size: size, weight: .black)
    }
}

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
    /// Text clips with scratch style — re-rasterized every frame in tick().
    private var scratchClips: [EngineClipAddress: (clip: Clip, start: Double, end: Double)] = [:]

    /// Stored canvas size so tick() can re-rasterize scratch text without the
    /// rebuild() parameter being in scope.
    private var canvas: CGSize = CGSize(width: 1080, height: 1920)

    /// Deterministic per-frame hash matching text_anim.cpp hash01().
    private static func hash01(_ i: Int, _ salt: Int) -> Float {
        var x = (UInt32(truncatingIfNeeded: i) &* 2654435761) ^ (UInt32(truncatingIfNeeded: salt) &* 40503)
        x ^= x >> 13; x &*= 0x5bd1e995; x ^= x >> 15
        return Float(x & 0xFFFFFF) / Float(0x1000000)
    }

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
        self.canvas = canvas
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
        // Scratch-on-film clips bypass the cache — they're re-rasterized per
        // frame in tick() and tracked in scratchClips instead.
        var live: Set<EngineClipAddress> = []
        var liveScratch: Set<EngineClipAddress> = []
        for tr in tracks where tr.kind == .lyric {
            for c in tr.clips {
                guard let a = c.address, a != excludingText else { continue }
                live.insert(a)
                if c.clipStyle == "scratch" || c.clipStyle == "scratch-raw" {
                    liveScratch.insert(a)
                    scratchClips[a] = (clip: c, start: c.start, end: c.end)
                    // Submit an initial frame so the layer isn't blank before
                    // the first tick(); tick() keeps it fresh thereafter.
                    if c.clipStyle == "scratch-raw" {
                        if let pb = Self.rasterScratchRawText(c, canvas: canvas, frame: 0) {
                            engine?.submitLayerFrame(track: a.track, clip: a.clip, pb, hostTime: -1)
                        }
                    } else {
                        if let pb = Self.rasterScratchText(c, canvas: canvas, frame: 0) {
                            engine?.submitLayerFrame(track: a.track, clip: a.clip, pb, hostTime: -1)
                        }
                    }
                    continue
                }
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
        for (a, _) in scratchClips where !liveScratch.contains(a) {
            engine?.submitLayerFrame(track: a.track, clip: a.clip, nil, hostTime: -1)
            scratchClips.removeValue(forKey: a)
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
        // Scratch text: re-rasterize with per-frame scratches
        for (a, info) in scratchClips {
            guard playhead >= info.start, playhead < info.end else { continue }
            let localT = playhead - info.start
            let frame = Int(localT * 24)
            let pb: CVPixelBuffer?
            if info.clip.clipStyle == "scratch-raw" {
                pb = Self.rasterScratchRawText(info.clip, canvas: canvas, frame: frame)
            } else {
                pb = Self.rasterScratchText(info.clip, canvas: canvas, frame: frame)
            }
            if let pb { engine.submitLayerFrame(track: a.track, clip: a.clip, pb, hostTime: playhead) }
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
            .font: c.subFont.isEmpty ? UIFont.systemFont(ofSize: lay.fontSize, weight: .black)
                 : DisplayFonts.font(c.subFont, size: lay.fontSize),
            .foregroundColor: UIColor.white, .paragraphStyle: para,
            .shadow: { let s = NSShadow(); s.shadowColor = UIColor.black.withAlphaComponent(0.55)
                       s.shadowBlurRadius = canvas.width * 0.02; s.shadowOffset = .zero; return s }(),
        ]
        (c.label as NSString).draw(in: lay.rect, withAttributes: attrs)
        UIGraphicsPopContext()
        return pb
    }

    /// Per-frame scratch-on-film raster: same text draw as `rasterText`, then
    /// switch to `.destinationOut` blend and stroke per-frame scratch lines so
    /// they erase text pixels (transparent scratches showing through to video).
    static func rasterScratchText(_ c: Clip, canvas: CGSize = CGSize(width: 1080, height: 1920),
                                  frame: Int) -> CVPixelBuffer? {
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

        // ── Per-frame scratch lines: erase parts of the text ──────────
        ctx.setBlendMode(.destinationOut)
        let nScratches = 12 + frame % 8
        for i in 0..<nScratches {
            let sx = CGFloat(hash01(i, frame)) * lay.rect.width
            let sy = CGFloat(hash01(i + 7, frame)) * lay.rect.height
            let ang = (CGFloat(hash01(i + 13, frame)) - 0.5) * .pi * 0.3
            let len = lay.rect.width * (0.2 + CGFloat(hash01(i + 19, frame)) * 0.6)
            ctx.move(to: CGPoint(x: lay.rect.minX + sx, y: lay.rect.minY + sy))
            ctx.addLine(to: CGPoint(x: lay.rect.minX + sx + cos(ang) * len,
                                    y: lay.rect.minY + sy + sin(ang) * len))
        }
        ctx.setStrokeColor(UIColor.white.cgColor)   // alpha=1 → full erasure
        ctx.setLineWidth(1.5)
        ctx.strokePath()
        ctx.setBlendMode(.normal)

        UIGraphicsPopContext()
        return pb
    }

    /// Per-frame scratch-raw raster: each letter IS scratches. We render each
    /// glyph to a small coverage bitmap, sample it, and draw parallel hatch
    /// lines (vertical by default, horizontal for wide glyphs) only where the
    /// glyph has alpha. Sparse spacing + thin strokes keep letters legible;
    /// jitter + gaps add the hand-scratched feel. No mask tricks — the letters
    /// are literally drawn from scratch lines. Hard cut on/off per letter
    /// (staggered, no fade).
    static func rasterScratchRawText(_ c: Clip, canvas: CGSize = CGSize(width: 1080, height: 1920),
                                     frame: Int) -> CVPixelBuffer? {
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
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        let lay = TextLayoutModel.layout(c.label, clip: c, in: canvas)
        let font = DisplayFonts.font(c.subFont, size: lay.fontSize)
        let localT = Double(frame) / 24.0
        let stagger = 0.06
        let threshold: UInt8 = 50
        let spacing = 5
        let para = NSMutableParagraphStyle(); para.alignment = lay.alignment
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: UIColor.white, .paragraphStyle: para,
        ]
        let glyphH = lay.fontSize * 1.2
        let strokeCol = UIColor.white.cgColor

        var gi = 0
        var curX = lay.rect.minX
        for ch in c.label {
            let charStr = String(ch)
            let charW = (charStr as NSString).size(withAttributes: attrs).width
            if ch == " " { curX += charW; continue }

            // Hard cut: letter is on or off, no fade
            let et = localT - Double(gi) * stagger
            if et < 0 { curX += charW; gi += 1; continue }

            // Render glyph to small bitmap for coverage sampling
            let bmpW = max(2, Int(charW) + 4)
            let bmpH = max(2, Int(glyphH) + 4)
            var bmpData = [UInt8](repeating: 0, count: bmpW * bmpH * 4)
            if let bmp = CGContext(data: &bmpData, width: bmpW, height: bmpH,
                                   bitsPerComponent: 8, bytesPerRow: bmpW * 4,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue |
                                               CGBitmapInfo.byteOrder32Little.rawValue) {
                bmp.clear(CGRect(x: 0, y: 0, width: bmpW, height: bmpH))
                UIGraphicsPushContext(bmp)
                bmp.translateBy(x: 0, y: CGFloat(bmpH))
                bmp.scaleBy(x: 1, y: -1)
                (charStr as NSString).draw(in: CGRect(x: 2, y: 2, width: charW, height: glyphH),
                                           withAttributes: attrs)
                UIGraphicsPopContext()

                // Flip coverage map so row 0 = top (matches main ctx)
                var cov = [UInt8](repeating: 0, count: bmpW * bmpH)
                for y in 0..<bmpH {
                    for x in 0..<bmpW {
                        cov[y * bmpW + x] = bmpData[((bmpH - 1 - y) * bmpW + x) * 4]
                    }
                }
                let sx = charW / CGFloat(bmpW)
                let sy = glyphH / CGFloat(bmpH)
                let horizontal = charW > glyphH * 1.3

                // Interior hatch only — sparse, thin, rough
                if horizontal {
                    for y in stride(from: 0, to: bmpH, by: spacing) {
                        var seg = -1
                        for x in 0...bmpW {
                            let c = (x < bmpW) ? cov[y * bmpW + x] : UInt8(0)
                            if c > threshold {
                                if seg < 0 { seg = x }
                            } else if seg >= 0 {
                                let si = y / spacing
                                if Self.hash01(gi * 17 + si, frame) > 0.08 {
                                    let th = 1 + CGFloat(Self.hash01(gi * 31 + si, frame + 13)) * 1
                                    let jy = (CGFloat(Self.hash01(gi * 43 + si, frame + 27)) - 0.5) * 2
                                    ctx.setStrokeColor(strokeCol); ctx.setLineWidth(th)
                                    ctx.move(to: CGPoint(x: curX + CGFloat(seg) * sx,
                                                         y: lay.rect.minY + CGFloat(y) * sy + jy))
                                    ctx.addLine(to: CGPoint(x: curX + CGFloat(x - 1) * sx,
                                                         y: lay.rect.minY + CGFloat(y) * sy + jy))
                                    ctx.strokePath()
                                }
                                seg = -1
                            }
                        }
                    }
                } else {
                    for x in stride(from: 0, to: bmpW, by: spacing) {
                        var seg = -1
                        for y in 0...bmpH {
                            let c = (y < bmpH) ? cov[y * bmpW + x] : UInt8(0)
                            if c > threshold {
                                if seg < 0 { seg = y }
                            } else if seg >= 0 {
                                let si = x / spacing
                                if Self.hash01(gi * 17 + si, frame) > 0.08 {
                                    let th = 1 + CGFloat(Self.hash01(gi * 31 + si, frame + 13)) * 1
                                    let jx = (CGFloat(Self.hash01(gi * 43 + si, frame + 27)) - 0.5) * 2
                                    ctx.setStrokeColor(strokeCol); ctx.setLineWidth(th)
                                    ctx.move(to: CGPoint(x: curX + CGFloat(x) * sx + jx,
                                                         y: lay.rect.minY + CGFloat(seg) * sy))
                                    ctx.addLine(to: CGPoint(x: curX + CGFloat(x) * sx + jx,
                                                         y: lay.rect.minY + CGFloat(y - 1) * sy))
                                    ctx.strokePath()
                                }
                                seg = -1
                            }
                        }
                    }
                }
            }
            curX += charW
            gi += 1
        }
        UIGraphicsPopContext()
        return pb
    }
}
