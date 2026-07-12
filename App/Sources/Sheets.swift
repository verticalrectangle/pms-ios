//  Sheets.swift
//  Bottom-sheet surfaces: a shared GlassSheet chrome + the Agent, Media bin,
//  Lyric styling, and Export sheets. Everything visible is backed by a real
//  engine lever or Apple backend; features whose backend doesn't exist on iOS
//  yet are shown as concretely unavailable — never faked.

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Shared sheet chrome

struct GlassSheet<Content: View>: View {
    let title: String
    var eyebrow: String? = nil
    var full: Bool = false
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AtmosphereView()
            VStack(spacing: 0) {
                Capsule().fill(Theme.lineStrong).frame(width: 38, height: 5).padding(.top, 9)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let eyebrow { Text(eyebrow).font(.label(9)).foregroundStyle(Theme.accent) }
                        Text(title).font(.disp(24)).textCase(.uppercase).foregroundStyle(.white)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 16)).foregroundStyle(Theme.txtBody)
                            .frame(width: 38, height: 38).glass(19)
                    }
                }
                .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 12)
                ScrollView { content().padding(.horizontal, 16).padding(.bottom, 24) }
                    .scrollIndicators(.hidden)
            }
        }
        .presentationDetents(full ? [.large] : [.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.clear)
    }
}

// MARK: - Agent

/// On-device AI actions. Every model-backed action requires a model pack that
/// is not bundled on iOS yet, so the honest state is "unavailable, here's why"
/// — never a fake transcript or a silent no-op.
struct AgentSheet: View {
    @ObservedObject var model: EditorModel

    private let plannedActions: [(title: String, model: String, icon: String)] = [
        ("Describe scenes", "Moondream2", "eye"),
        ("Remove background", "Person matte", "person.crop.rectangle"),
        ("Analyze beats", "beat / RMS", "metronome"),
        ("Auto captions", "whisper.cpp", "captions.bubble"),
    ]

    var body: some View {
        GlassSheet(title: "Agent", eyebrow: "ON-DEVICE MODELS", full: true) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle").foregroundStyle(Theme.txtMuted)
                    Text("Model packs aren't installed on this device yet. These actions unlock when a pack is downloaded.")
                        .font(.system(size: 13)).foregroundStyle(Theme.txtBody)
                }
                .padding(12).glass(12, flat: true)

                Text("Actions (unavailable)").font(.label(9)).foregroundStyle(Theme.txtMuted)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(plannedActions, id: \.title) { action in
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: action.icon).font(.system(size: 18)).foregroundStyle(Theme.txtMuted)
                                .frame(width: 34, height: 34)
                                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.04)))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(action.title).font(.disp(13)).textCase(.uppercase).foregroundStyle(Theme.txtMuted)
                                Text(action.model).font(.num(11)).foregroundStyle(Theme.txtGhost).lineLimit(1)
                            }
                            Text("needs model pack").font(.label(8)).foregroundStyle(Theme.txtGhost)
                        }
                        .padding(12).frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
                        .glass(Theme.rCard)
                        .opacity(0.55)
                    }
                }
            }
        }
    }
}

// MARK: - Media bin (engine project bin + native pickers)

struct MediaSheet: View {
    @ObservedObject var model: EditorModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var showFileImporter = false

    private var binItems: [String] { model.bin }

    var body: some View {
        GlassSheet(title: "Project Bin", eyebrow: "MEDIA LIBRARY · \(binItems.count) ITEMS", full: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    PhotosPicker(selection: $pickerItem, matching: .videos) {
                        importButton("Photos", icon: "photo.badge.plus")
                    }
                    Button { showFileImporter = true } label: {
                        importButton("Files", icon: "folder.badge.plus")
                    }
                }

                if binItems.isEmpty {
                    Text("Nothing in the bin yet — import from Photos or Files.")
                        .font(.system(size: 13)).foregroundStyle(Theme.txtMuted)
                        .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 26)
                } else {
                    Text("Tap to place at the playhead").font(.label(9)).foregroundStyle(Theme.txtMuted)
                    VStack(spacing: 8) {
                        ForEach(binItems, id: \.self) { path in
                            binRow(path)
                        }
                    }
                }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let movie = try? await item.loadTransferable(type: PickedMovie.self) {
                    model.importVideo(movie.url)
                }
                pickerItem = nil
            }
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.movie, .audio]) { result in
            if case .success(let url) = result {
                let scoped = url.startAccessingSecurityScopedResource()
                model.importVideo(url)   // copies into the project sandbox
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
        }
    }

    private func importButton(_ label: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Theme.accent)
            Text(label).font(.disp(14)).foregroundStyle(Theme.txt)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12).glass(13)
    }

    private func binRow(_ path: String) -> some View {
        let url = URL(fileURLWithPath: path)
        let isAudio = ["wav", "mp3", "m4a", "aac", "flac"].contains(url.pathExtension.lowercased())
        let onTimeline = model.tracks.flatMap(\.clips).contains { $0.sourceURL?.path == path }
        return HStack(spacing: 10) {
            Image(systemName: isAudio ? "waveform" : "film")
                .font(.system(size: 15)).foregroundStyle(Theme.txtBody)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent).font(.label(10)).tracking(0.4).foregroundStyle(Theme.txt).lineLimit(1)
                if onTimeline { Text("on timeline").font(.num(10)).foregroundStyle(Theme.accent) }
            }
            Spacer()
            Image(systemName: "plus").font(.system(size: 13)).foregroundStyle(Theme.txtMuted)
        }
        .padding(9).glass(12, flat: true)
        .contentShape(Rectangle())
        .onTapGesture { model.placeBinItem(path) }
        .contextMenu {
            Button(role: .destructive) {
                model.engine.send("remove_from_bin", ["path": path])
                model.refresh(rebuildPlayer: false)
            } label: { Label("Remove from bin", systemImage: "trash") }
        }
    }
}

// MARK: - Lyric styling

struct LyricsSheet: View {
    @ObservedObject var model: EditorModel
    @State private var anim = "none"
    private let anims = ["none", "fade", "glitch", "typewriter", "bounce", "scale", "slide", "wave", "jitter", "scratch", "scratch-raw"]

    /// Engine-generated (managed) lyric clips exist → typography presets apply.
    private var hasManagedLyrics: Bool {
        model.tracks.flatMap(\.clips).contains { c in
            guard let a = c.address else { return false }
            return model.engineClipType(a) == "lyrics"
        }
    }
    private var selectedText: Clip? { model.selectedLyricClip }

    var body: some View {
        GlassSheet(title: "Text Style", eyebrow: "TITLES · ANIMATION", full: true) {
            VStack(alignment: .leading, spacing: 18) {
                if let clip = selectedText {
                    Text("Animation — \(clip.label)").font(.label(9)).foregroundStyle(Theme.txtMuted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(anims, id: \.self) { a in
                                Chip(text: a.capitalized, on: anim == a) {
                                    anim = a
                                    model.setClipStyle(clip.id, style: a)
                                }
                            }
                        }
                    }
                } else {
                    Text("Select a title on the timeline to style it, or add one with the Text button.")
                        .font(.system(size: 13)).foregroundStyle(Theme.txtMuted)
                        .padding(.vertical, 8)
                }

                if hasManagedLyrics {
                    Text("Typography preset").font(.label(9)).foregroundStyle(Theme.txtMuted)
                    HStack(spacing: 8) {
                        ForEach(["flash", "apple", "spotify", "clean"], id: \.self) { p in
                            Button {
                                model.engine.send("set_typography_preset", ["preset": p])
                                model.refresh(rebuildPlayer: false)
                            } label: {
                                Text(p.uppercased()).font(.label(9)).tracking(0.4).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                                    .glass(12)
                            }
                        }
                    }
                } else {
                    Label("Typography presets style engine-generated lyric tracks — none in this project.",
                          systemImage: "info.circle")
                        .font(.label(9)).tracking(0.4).foregroundStyle(Theme.txtMuted)
                        .padding(11).glass(12, flat: true)
                }
            }
        }
        .onAppear {
            if let clip = selectedText, let a = clip.address,
               let style = model.engineClipStyle(a) { anim = style }
        }
    }
}

// MARK: - Export (Apple AVAssetReader/Writer backend)

struct ExportSheet: View {
    @ObservedObject var model: EditorModel
    @State private var phase: Phase = .idle
    @State private var pct = 0.0
    @State private var outURL: URL?
    @State private var errorText: String?
    @State private var saved = false
    @State private var cancelFlag = CancelFlag()
    enum Phase { case idle, rendering, done }

    final class CancelFlag: @unchecked Sendable { var cancelled = false }

    init(model: EditorModel) { self.model = model }

    private var hasVideo: Bool { !model.videoSegments.isEmpty }

    /// Rough storage check: exporting needs at least ~200 MB free.
    private var lowStorage: Bool {
        let free = (try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage) ?? nil
        if let free { return free < 200_000_000 }
        return false
    }

    var body: some View {
        GlassSheet(title: "Export", eyebrow: "TIMELINE → H.264 / AAC · MP4") {
            VStack(spacing: 14) {
                if !hasVideo {
                    Text("Import a clip to export.")
                        .font(.num(13)).foregroundStyle(Theme.txtMuted)
                        .frame(maxWidth: .infinity).padding(.vertical, 22)
                } else {
                    switch phase {
                    case .idle:
                        VStack(spacing: 6) {
                            Text(String(format: "%.1fs · %@", model.duration, model.format.resolution))
                                .font(.num(13)).foregroundStyle(Theme.txtMuted)
                        }.frame(maxWidth: .infinity).padding(.vertical, 8)
                        if lowStorage {
                            Label("Storage is nearly full — export may fail.", systemImage: "externaldrive.badge.exclamationmark")
                                .font(.label(9)).foregroundStyle(Color(red: 1, green: 0.7, blue: 0.4))
                        }
                        Button { startRender() } label: {
                            HStack(spacing: 10) { Image(systemName: "square.and.arrow.up"); Text("Export MP4").font(.disp(16)) }
                                .foregroundStyle(Theme.accent).frame(maxWidth: .infinity).padding(.vertical, 15).glass(15, active: true)
                        }
                        if let errorText {
                            Text(errorText).font(.num(12)).foregroundStyle(Color(red: 1, green: 0.5, blue: 0.5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    case .rendering:
                        VStack(alignment: .leading, spacing: 9) {
                            HStack { Text("EXPORTING…").font(.label(10)).foregroundStyle(Theme.accent); Spacer(); Text("\(Int(pct * 100))%").font(.num(13)).foregroundStyle(Theme.accent) }
                            ProgressView(value: pct).tint(Theme.accent)
                            Button { cancelFlag.cancelled = true } label: {
                                Text("Cancel").font(.label(11)).foregroundStyle(Theme.txtMuted)
                                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
                            }
                        }.padding(16).glass(15, flat: true)
                    case .done:
                        VStack(spacing: 14) {
                            Image(systemName: saved ? "checkmark.seal.fill" : "square.and.arrow.up.circle")
                                .font(.system(size: 34)).foregroundStyle(saved ? Theme.accent : Color(red: 1, green: 0.7, blue: 0.4))
                            Text(saved ? "Saved to Photos" : "Exported — share it below").font(.disp(18)).foregroundStyle(Theme.txt)
                            if !saved {
                                Text("Photos permission was denied, so the file wasn't added to your library.")
                                    .font(.num(11)).foregroundStyle(Theme.txtMuted).multilineTextAlignment(.center)
                            }
                            if let outURL {
                                Text(sizeString(outURL)).font(.num(12)).foregroundStyle(Theme.txtMuted)
                                HStack(spacing: 10) {
                                    ShareLink(item: outURL) {
                                        HStack(spacing: 8) { Image(systemName: "square.and.arrow.up"); Text("Share").font(.disp(15)) }
                                            .foregroundStyle(Theme.accent).frame(maxWidth: .infinity).padding(.vertical, 13).glass(15, active: true)
                                    }
                                    if saved {
                                        Button { openGallery() } label: {
                                            HStack(spacing: 8) { Image(systemName: "photo.on.rectangle.angled"); Text("Open Gallery").font(.disp(15)) }
                                                .foregroundStyle(Theme.txt).frame(maxWidth: .infinity).padding(.vertical, 13).glass(15)
                                        }
                                    }
                                }
                                Button { phase = .idle } label: {
                                    Text("Export again").font(.label(11)).foregroundStyle(Theme.txtMuted)
                                }
                            }
                        }.padding(18).frame(maxWidth: .infinity).glass(15)
                    }
                }
            }
        }
    }

    private func sizeString(_ url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attrs?[.size] as? Int) ?? 0
        return url.lastPathComponent + " · " + ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func startRender() {
        errorText = nil; phase = .rendering; pct = 0
        cancelFlag = CancelFlag()
        let flag = cancelFlag
        let segments = model.videoSegments
        let audioOnly = model.audioOnlySegments

        // The engine scene composites layers exactly like preview: the export
        // loop re-submits base + overlay video frames per output frame, and
        // text rasters once. Gather everything from the projection up front.
        let primary = model.primaryVideoEngineTrack
        var overlays: [VideoExporter.OverlayLayer] = []
        var baseSpans: [VideoExporter.BaseSpan] = []
        var texts: [VideoExporter.TextLayer] = []
        for tr in model.tracks {
            for c in tr.clips {
                guard let a = c.address else { continue }
                switch tr.kind {
                case .video where tr.engineIndex == primary:
                    baseSpans.append((c.start, c.end, a.track, a.clip))
                case .video:
                    if let url = c.sourceURL, overlays.count < LayerFeeder.overlayVideoCap {
                        overlays.append(.init(track: a.track, clip: a.clip, url: url,
                                              start: c.start, end: c.end,
                                              inPoint: c.sourceStart, speed: c.speed))
                    }
                case .lyric:
                    texts.append(.init(track: a.track, clip: a.clip, clipModel: c))
                default: break
                }
            }
        }

        model.syncLiveFX()                    // legacy fallback path only
        model.exporting = true                // suspend the live canvas → export owns the engine
        model.video?.suspended = true
        model.layers?.suspended = true
        model.engine.setTicksPaused(true)     // stop the engine tick too (exclusive access)
        Task {
            defer {
                model.engine.setTicksPaused(false)
                model.video?.suspended = false
                model.layers?.suspended = false
                model.exporting = false
                model.refresh()               // re-submit preview layers fresh
            }
            do {
                let url = try await VideoExporter.export(segments, audioOnly: audioOnly,
                                                         overlays: overlays, texts: texts,
                                                         baseSpans: baseSpans,
                                                         engine: model.engine, size: model.format.pixelSize,
                                                         isCancelled: { flag.cancelled }) { p in pct = p }
                outURL = url
                saved = await VideoExporter.saveToPhotos(url)   // add-only; share path remains if denied
                phase = .done
            } catch {
                errorText = error.localizedDescription
                phase = .idle
            }
        }
    }

    private func openGallery() {
        if let u = URL(string: "photos-redirect://") { UIApplication.shared.open(u) }
    }
}
