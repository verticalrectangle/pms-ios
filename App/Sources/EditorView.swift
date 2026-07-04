//  EditorView.swift
//  The editor: canvas (engine-composited), transport, timeline, dock, inspector,
//  the busy bar, and sheet routing. Tap the canvas to expand a fullscreen player;
//  swipe it down to dismiss.

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// Publishes the on-screen keyboard height so a bar can be lifted by exactly
/// that amount (the rest of the UI stays put).
final class KeyboardObserver: ObservableObject {
    @Published var height: CGFloat = 0
    init() {
        let c = NotificationCenter.default
        c.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] n in
            guard let f = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            self?.height = max(0, UIScreen.main.bounds.height - f.minY)
        }
        c.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            self?.height = 0
        }
    }
}

/// A picked video, copied into our sandbox so AVFoundation can read it.
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let dst = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "." + received.file.pathExtension)
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: received.file, to: dst)
            return Self(url: dst)
        }
    }
}

struct EditorView: View {
    @StateObject private var model: EditorModel
    @ObservedObject var engine: EngineStore
    private let projectName: String

    @State private var fullscreen = false
    @State private var camera: CameraCapture?
    @State private var cameraOn = false
    @State private var pickerItem: PhotosPickerItem?
    @StateObject private var keyboard = KeyboardObserver()

    private func toggleCamera() {
        if cameraOn {
            camera?.stop(); camera = nil; cameraOn = false
        } else {
            let c = CameraCapture(engine: engine)
            try? c.start(position: .back)
            camera = c; cameraOn = true
        }
    }

    init(project: Project, engine: EngineStore) {
        self.engine = engine
        self.projectName = project.isNew ? "" : project.name   // unnamed until saved with a title
        _model = StateObject(wrappedValue: EditorModel(project: project, engine: engine))
    }

    private var t: Double { model.playhead }

    private let tools: [(EditorSheet, String, String)] = [
        (.media,  "square.stack",       "Media"),
        (.fx,     "sparkles",           "FX"),
        (.lyrics, "textformat",         "Text"),
        (.agent,  "brain.head.profile", "Agent"),
    ]

    var body: some View {
        // Canvas sized from UIScreen (absolute) — flex-sizing is unreliable in
        // this VStack. The system nav bar (back + share) and bottom bar (tools)
        // are native toolbars, so safe areas and Liquid Glass are handled by iOS.
        ZStack {
            VStack(spacing: 10) {
                canvas(box: canvasBox())
                TransportBar(model: model, engine: engine).padding(.horizontal, 16)
                timeline
                if let clip = model.selectedClip {
                    ClipActionBar(model: model, clip: clip)
                        .padding(.horizontal, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if model.selectedLyricClip == nil, let sel = model.selectedID {
                    InspectorView(model: model, brickID: sel)   // bricks (text bar floats separately)
                        .padding(.horizontal, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 6)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.selectedID)
            .ignoresSafeArea(.keyboard, edges: .bottom)   // the UI stays put; only the text bar floats up

            VStack {
                BusyBar(busy: engine.busy).padding(.horizontal, 12).padding(.top, 8)
                Spacer()
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: engine.busy?.label)

            // The text edit bar floats just above the keyboard (respects the
            // keyboard safe area) while the rest of the UI stays put — nothing jumps.
            if let lyric = model.selectedLyricClip {
                VStack {
                    Spacer()
                    LyricEditBar(model: model, clip: lyric).padding(.horizontal, 12)
                }
                .padding(.bottom, keyboard.height > 0 ? keyboard.height + 4 : 8)   // flush on the keyboard
                .ignoresSafeArea(.keyboard, edges: .bottom)   // we lift it ourselves
                .animation(.easeOut(duration: 0.22), value: keyboard.height)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(20)
            }

            if fullscreen {
                FullscreenPlayer(engine: engine, model: model, isPresented: $fullscreen)
                    .zIndex(50)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.selectedLyricClip?.id)
        .background(AtmosphereView().ignoresSafeArea())
        // Tap empty space while editing a title → commit + dismiss keyboard (text
        // is saved live). Gated so it never interferes with normal use.
        .onTapGesture { if model.selectedLyricClip != nil { model.selectedID = nil } }
        .navigationTitle(projectName)
        .navigationBarTitleDisplayMode(.inline)
        // Hide the tool dock while editing a title so the edit bar owns the
        // bottom cleanly (nothing to float over).
        .toolbar(model.selectedLyricClip != nil ? .hidden : .visible, for: .bottomBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!model.canUndo)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!model.canRedo)
            }
            ToolbarItem(placement: .topBarTrailing) {
                PhotosPicker(selection: $pickerItem, matching: .videos) {
                    Image(systemName: "photo.badge.plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { toggleCamera() } label: {
                    Image(systemName: cameraOn ? "camera.fill" : "camera")
                }
                .tint(cameraOn ? Theme.accent : Theme.txtBody)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.activeSheet = .export } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                ForEach(Array(tools.enumerated()), id: \.offset) { i, item in
                    if i > 0 { Spacer() }
                    Button {
                        if item.0 == .lyrics { model.addTextClip() }   // Text → add a title at the playhead
                        else { model.activeSheet = (model.activeSheet == item.0) ? nil : item.0 }
                    } label: {
                        Label(item.2, systemImage: item.1)
                    }
                    .tint(model.activeSheet == item.0 ? Theme.accent : Theme.txtBody)
                }
            }
        }
        .sheet(item: $model.activeSheet) { sheet in
            switch sheet {
            case .media:  MediaSheet()
            case .fx:     FXSheet(model: model)
            case .lyrics: LyricsSheet(model: model)
            case .agent:  AgentSheet(model: model)
            case .export: ExportSheet(model: model)
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let movie = try? await item.loadTransferable(type: PickedMovie.self) {
                    model.importVideo(movie.url)
                }
            }
        }
        .onAppear { engine.startMockMeters() }
    }

    /// Largest aspect-correct canvas box that fits ~42% of the screen height
    /// and the available width (minus padding).
    private func canvasBox() -> CGSize {
        let screen = UIScreen.main.bounds.size
        let maxH = screen.height * 0.40
        let maxW = screen.width - 28
        let h = min(maxH, maxW / model.format.aspect)
        return CGSize(width: h * model.format.aspect, height: h)
    }

    // MTKView (UIViewRepresentable) ignores .aspectRatio, so the canvas is
    // sized explicitly (box computed from the root geometry).
    private func canvas(box: CGSize) -> some View {
        MetalPreview(store: engine)
            .frame(width: box.width, height: box.height)
            .overlay(CanvasChrome(clipLabel: model.activeVideoLabel(at: t),
                                  activeBricks: model.activeBricks(at: t)))
            .overlay(LyricOverlay(clips: model.activeLyrics(at: t), width: box.width))
            .overlay {
                if !model.videoLoaded {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 34, weight: .light))
                        Text("Tap ＋ to add a clip").font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Theme.txtMuted)
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.rCard))
            .overlay(RoundedRectangle(cornerRadius: Theme.rCard).strokeBorder(Theme.line))
            .frame(maxWidth: .infinity)   // centre horizontally
            .contentShape(Rectangle())
            .onTapGesture {
                if model.selectedLyricClip != nil { model.selectedID = nil }   // commit text edit
                else { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { fullscreen = true } }
            }
    }

    /// Fit the timeline to its tracks (ruler + lanes + spacing + vpad), so lower
    /// tracks (text/audio) aren't clipped. Clamped so it never crushes the canvas.
    private var timelineHeight: CGFloat {
        func laneH(_ k: TrackKind) -> CGFloat { switch k { case .fxRail: 30; case .video: 52; case .lyric: 40; case .audio: 34 } }
        let content = 34 + model.tracks.reduce(0) { $0 + laneH($1.kind) + 3 } + 12
        return min(max(content, 132), 252)
    }

    private var timeline: some View {
        TimelineView(model: model, engine: engine)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .frame(height: timelineHeight)
            .glass(18, flat: true, sheer: true)   // thin frost so the atmosphere reads behind it
            .padding(.horizontal, 8)
            .onTapGesture { /* tap-away handled inside */ }
    }

}

// MARK: - Clip action bar (shown when a timeline clip is selected)

private struct ClipActionBar: View {
    @ObservedObject var model: EditorModel
    let clip: Clip
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(clip.label).font(.label(10)).tracking(0.5).foregroundStyle(Theme.txt).lineLimit(1)
                Text(String(format: "%.1fs", clip.duration)).font(.num(9)).foregroundStyle(Theme.txtMuted)
            }
            Spacer(minLength: 8)
            Button { model.splitAtPlayhead() } label: {
                Label("Split", systemImage: "scissors").font(.label(11)).tracking(0.5)
            }.tint(Theme.txtBody)
            Button(role: .destructive) { model.deleteSelectedClip() } label: {
                Label("Delete", systemImage: "trash").font(.label(11)).tracking(0.5)
            }.tint(Color(red: 1, green: 0.5, blue: 0.5))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glass(16)
    }
}

// MARK: - Text edit bar (shown when a text/lyric clip is selected)

private struct LyricEditBar: View {
    @ObservedObject var model: EditorModel
    let clip: Clip
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "textformat").font(.system(size: 15)).foregroundStyle(Theme.accent)
            TextField("Title text", text: $text)
                .textInputAutocapitalization(.characters)
                .submitLabel(.done)
                .font(.label(13)).foregroundStyle(Theme.txt)
                .focused($focused)
                .onChange(of: text) { _, v in model.setClipText(clip.id, v) }
                .onSubmit { model.selectedID = nil }   // Return commits + deselects
            Button(role: .destructive) { model.deleteClipAnywhere(clip.id) } label: {
                Image(systemName: "trash").font(.system(size: 14))
            }.tint(Color(red: 1, green: 0.5, blue: 0.5))
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .glass(16)
        // Keyboard only right after CREATING the title; selecting it later just
        // shows the bar (tap the field to edit) so the timeline stays free to move it.
        .onAppear { text = clip.label; if model.focusNewText { focused = true; model.focusNewText = false } }
    }
}

// MARK: - Fullscreen player (tap-expand / swipe-down dismiss)

private struct FullscreenPlayer: View {
    @ObservedObject var engine: EngineStore
    @ObservedObject var model: EditorModel
    @Binding var isPresented: Bool
    @State private var drag: CGFloat = 0

    private var t: Double { model.playhead }

    var body: some View {
        let progress = min(1, max(0, drag / 400))
        ZStack {
            Color.black.opacity(Double(1 - progress * 0.5)).ignoresSafeArea()
            MetalPreview(store: engine)
                .aspectRatio(model.format.aspect, contentMode: .fit)
                .overlay(controls)
                .scaleEffect(1 - progress * 0.15)
                .offset(y: drag)
        }
        .gesture(
            DragGesture()
                .onChanged { drag = max(0, $0.translation.height) }
                .onEnded { v in
                    if v.translation.height > 120 || v.predictedEndTranslation.height > 300 {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isPresented = false }
                    } else { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { drag = 0 } }
                }
        )
    }

    private var controls: some View {
        ZStack {
            VStack {
                Image(systemName: "chevron.compact.up").foregroundStyle(.white.opacity(0.5))
                Text("SWIPE DOWN TO CLOSE").font(.label(9)).tracking(1.4).foregroundStyle(.white.opacity(0.55))
                Spacer()
            }.padding(.top, 24)

            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22)).foregroundStyle(.white)
                    .frame(width: 62, height: 62).background(.ultraThinMaterial, in: Circle())
            }

            VStack {
                Spacer()
                Slider(value: Binding(get: { t }, set: { model.seek($0) }), in: 0...model.duration).tint(Theme.accent)
                HStack {
                    Text(fullTC(t)).font(.num(11)).foregroundStyle(.white)
                    Spacer()
                    Text(fullTC(model.duration)).font(.num(11)).foregroundStyle(.white.opacity(0.5))
                }
            }.padding(22)
        }
    }
}
