//  EditorView.swift
//  The editor: canvas (engine-composited), transport, timeline, dock, inspector,
//  the busy bar, and sheet routing. Tap the canvas to expand a fullscreen player;
//  swipe it down to dismiss.

import SwiftUI

struct EditorView: View {
    @StateObject private var model: EditorModel
    @ObservedObject var engine: EngineStore
    let onBack: () -> Void

    @State private var fullscreen = false

    init(project: Project, engine: EngineStore, onBack: @escaping () -> Void) {
        self.engine = engine
        self.onBack = onBack
        _model = StateObject(wrappedValue: EditorModel(project: project, engine: engine))
    }

    private var t: Double { engine.playing ? engine.playhead : model.localSeek }

    var body: some View {
        GeometryReader { geo in
        ZStack {
            AtmosphereView()

            // Explicit sizes off the root geometry — flex-sizing (GeometryReader
            // / aspectRatio / maxHeight) collapses in this VStack, so the canvas
            // is sized directly: the largest 9:16 box that fits ~half the height.
            VStack(spacing: 10) {
                topBar
                canvas(box: canvasBox(in: geo.size))
                TransportBar(model: model, engine: engine).padding(.horizontal, 16)
                timeline
                bottomStack
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .padding(.top, 8)

            VStack {
                BusyBar(busy: engine.busy).padding(.horizontal, 12).padding(.top, 56)
                Spacer()
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: engine.busy?.label)

            if fullscreen {
                FullscreenPlayer(engine: engine, model: model, isPresented: $fullscreen)
                    .zIndex(50)
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
        .onAppear { engine.startMockMeters() }
        }   // GeometryReader
    }

    /// Largest aspect-correct canvas box that fits ~half the screen height and
    /// the available width (minus padding).
    private func canvasBox(in size: CGSize) -> CGSize {
        let maxH = size.height * 0.44
        let maxW = size.width - 28
        let h = min(maxH, maxW / model.format.aspect)
        return CGSize(width: h * model.format.aspect, height: h)
    }

    private var topBar: some View {
        HStack {
            Button { onBack() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18)).foregroundStyle(Theme.txt)
                    .frame(width: 44, height: 44).glass(22)
            }.pressable()
            Spacer()
            Button { model.activeSheet = .export } label: {
                Image(systemName: "square.and.arrow.up").font(.system(size: 18)).foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44).glass(22)
            }.pressable()
        }
        .padding(.horizontal, 14)
    }

    // MTKView (UIViewRepresentable) ignores .aspectRatio, so the canvas is
    // sized explicitly (box computed from the root geometry).
    private func canvas(box: CGSize) -> some View {
        MetalPreview(store: engine)
            .frame(width: box.width, height: box.height)
            .overlay(CanvasChrome(clipLabel: model.activeVideoLabel(at: t),
                                  activeBricks: model.activeBricks(at: t)))
            .clipShape(RoundedRectangle(cornerRadius: Theme.rCard))
            .overlay(RoundedRectangle(cornerRadius: Theme.rCard).strokeBorder(Theme.line))
            .frame(maxWidth: .infinity)   // centre horizontally
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { fullscreen = true } }
    }

    private var timeline: some View {
        TimelineView(model: model, engine: engine)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .frame(height: 132)          // fixed — was maxHeight:.infinity, which crushed the canvas
            .glass(18, flat: true)
            .padding(.horizontal, 8)
            .onTapGesture { /* tap-away handled inside */ }
    }

    private var bottomStack: some View {
        VStack(spacing: 9) {
            if let sel = model.selectedID {
                InspectorView(model: model, brickID: sel)
            }
            ToolDock(model: model)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 30)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.selectedID)
    }
}

// MARK: - Fullscreen player (tap-expand / swipe-down dismiss)

private struct FullscreenPlayer: View {
    @ObservedObject var engine: EngineStore
    @ObservedObject var model: EditorModel
    @Binding var isPresented: Bool
    @State private var drag: CGFloat = 0

    private var t: Double { engine.playing ? engine.playhead : model.localSeek }

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
                Image(systemName: engine.playing ? "pause.fill" : "play.fill")
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
