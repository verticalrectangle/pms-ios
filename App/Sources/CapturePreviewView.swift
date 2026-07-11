// CapturePreviewView — post-recording preview: concatenated segment loop,
// Retake / Export / Add to Project actions, all in Liquid Glass chrome.

import SwiftUI
import AVFoundation
import UIKit

struct RecordedSegmentInfo: Identifiable {
    let id: Int
    let url: URL
    let duration: Double
}

struct CapturePreviewView: View {
    let segments: [RecordedSegmentInfo]
    let onRetake: () -> Void
    let onAddToProject: () -> Void
    let onClose: () -> Void

    @State private var player: AVPlayer?
    @State private var playerEndObserver: Any?
    @State private var exporting = false
    @State private var exportProgress: Double = 0
    @State private var savedToPhotos = false
    @State private var errorText: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                PlayerLayerView(player: player)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                HStack {
                    Button { onClose() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Circle().fill(.black.opacity(0.35)))
                    }
                    .pressable()
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)

                if let errorText {
                    ErrorBanner(text: errorText) { self.errorText = nil }
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }

                Spacer()

                HStack(spacing: 20) {
                    retakeButton
                    exportButton
                    addToProjectButton
                }
                .padding(.bottom, 40)
            }

            if savedToPhotos {
                VStack {
                    Spacer()
                    Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                        .font(.label(14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glass(18)
                        .padding(.bottom, 140)
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .task { await setupPlayer() }
        .onDisappear(perform: teardownPlayer)
    }

    private var retakeButton: some View {
        Button(action: onRetake) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.txt)
                .frame(width: 64, height: 64)
                .liquidGlassCircle(interactive: true, tint: Theme.accentA(0.3))
        }
        .pressable()
    }

    private var exportButton: some View {
        Button {
            Task { await exportVideo() }
        } label: {
            ZStack {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.txt)
                    .opacity(exporting ? 0 : 1)
                if exporting {
                    ProgressView(value: exportProgress, total: 1.0)
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.txt))
                        .frame(width: 32, height: 32)
                }
            }
            .frame(width: 64, height: 64)
            .liquidGlassCircle(interactive: true, tint: Theme.accentA(0.3))
        }
        .pressable()
        .disabled(exporting)
    }

    private var addToProjectButton: some View {
        Button(action: onAddToProject) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                Text("Add to Project")
                    .font(.disp(16))
                    .textCase(.uppercase)
            }
            .foregroundStyle(Theme.txt)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .glass(18, active: true)
        }
        .pressable()
    }

    @MainActor
    private func setupPlayer() async {
        guard !segments.isEmpty, !Task.isCancelled else { return }
        do {
            let (comp, vc) = try await buildComposition()
            let item = AVPlayerItem(asset: comp)
            item.videoComposition = vc
            let newPlayer = AVPlayer(playerItem: item)
            player = newPlayer
            playerEndObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main) { [self] _ in
                    player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in player?.play() }
                }
            newPlayer.play()
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func teardownPlayer() {
        if let observer = playerEndObserver {
            NotificationCenter.default.removeObserver(observer)
            playerEndObserver = nil
        }
        player?.pause()
        player = nil
    }

    @MainActor
    private func buildComposition() async throws -> (AVMutableComposition, AVMutableVideoComposition?) {
        var cursor: Double = 0
        var segs: [VideoPlayback.Segment] = []
        for seg in segments.sorted(by: { $0.id < $1.id }) {
            let start = cursor
            cursor += seg.duration
            segs.append(VideoPlayback.Segment(url: seg.url, start: start, sourceStart: 0, duration: seg.duration))
        }
        let (comp, vc) = try await VideoPlayback.buildComposition(segs)
        return (comp, vc)
    }

    @MainActor
    private func exportVideo() async {
        guard !exporting, !segments.isEmpty else { return }
        exporting = true
        exportProgress = 0
        savedToPhotos = false
        do {
            let (comp, vc) = try await buildComposition()
            let outURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
            guard let exporter = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else {
                errorText = "Could not create export session."
                exporting = false
                return
            }
            exporter.videoComposition = vc
            let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                exportProgress = Double(exporter.progress)
            }
            defer { progressTimer.invalidate(); exporting = false }
            try await exporter.export(to: outURL, as: .mp4)

            if await VideoExporter.saveToPhotos(outURL) {
                withAnimation { savedToPhotos = true }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation { savedToPhotos = false }
            } else {
                errorText = "Could not save to Photos."
            }
            try? FileManager.default.removeItem(at: outURL)
        } catch {
            exporting = false
            errorText = "Export failed: \(error.localizedDescription)"
        }
    }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .black
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        v.layer.addSublayer(layer)
        DispatchQueue.main.async { layer.frame = v.bounds }
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let playerLayer = uiView.layer.sublayers?.first as? AVPlayerLayer {
            playerLayer.frame = uiView.bounds
        }
    }
}
