// RecordView.swift — full-screen camera capture with live looks. The engine
// renders every preview frame (camera → pms_submit_camera_frame → live-FX
// stack → MetalPreview), so what you see is pixel-identical to playback and
// export. Looks are pushed record-scoped through set_live_fx (always-on, no
// timeline window); on dismiss the timeline-derived stack is restored. A
// finished take lands at the playhead with the active look welded on as a
// coupled Multi-FX brick — raw file, non-destructive filters.
import SwiftUI
import AVFoundation

struct RecordView: View {
    @ObservedObject var engine: EngineStore
    @ObservedObject var model: EditorModel
    @Binding var isPresented: Bool

    @State private var camera: CameraCapture?
    @State private var position: AVCaptureDevice.Position = .front
    @State private var recording = false
    @State private var recordStart: Date?
    @State private var elapsed: TimeInterval = 0
    @State private var category: Look.Category = .forYou
    @State private var look: Look = .none
    @State private var intensity: Double = 1.0
    @State private var countdown: Int?
    @State private var timerArmed = false     // 3-2-1 before recording
    @State private var errorText: String?

    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MetalPreview(store: engine)
                .aspectRatio(model.format.aspect, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let n = countdown {
                Text("\(n)")
                    .font(.system(size: 120, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 12)
                    .transition(.scale.combined(with: .opacity))
                    .id(n)   // re-animate each tick
            }

            VStack(spacing: 0) {
                topBar
                if let errorText {
                    ErrorBanner(text: errorText) { self.errorText = nil }
                        .padding(.horizontal, 12)
                }
                Spacer()
                if look != .none && !recording { intensityRow }
                lookRail
                recordRow
            }
        }
        .statusBarHidden()
        .onAppear(perform: startCamera)
        .onDisappear(perform: teardown)
        .onReceive(ticker) { _ in
            if let s = recordStart { elapsed = Date().timeIntervalSince(s) }
        }
        .onChange(of: look) { _, _ in pushLive(); haptic() }
        .onChange(of: intensity) { _, _ in pushLive() }
    }

    // MARK: chrome

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Circle().fill(.black.opacity(0.35)))
            }
            Spacer()
            if recording {
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text(timeString(elapsed)).font(.num(13)).foregroundStyle(.white)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.35)))
            }
            Spacer()
            Button { timerArmed.toggle(); haptic() } label: {
                Image(systemName: timerArmed ? "timer.circle.fill" : "timer")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(timerArmed ? Theme.accent : .white)
                    .padding(10)
                    .background(Circle().fill(.black.opacity(0.35)))
            }
            Button { flipCamera() } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Circle().fill(.black.opacity(0.35)))
            }
            .disabled(recording)   // flip mid-take would tear the writer session
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private var intensityRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "dial.low").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
            Slider(value: $intensity, in: 0.05...1).tint(Theme.accent)
            Text("\(Int(intensity * 100))%").font(.num(11)).foregroundStyle(.white.opacity(0.8))
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 6)
    }

    private var lookRail: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Look.Category.allCases) { c in
                        Button {
                            category = c
                            haptic()
                        } label: {
                            Text(c.rawValue)
                                .font(.label(11)).tracking(0.4)
                                .foregroundStyle(category == c ? .black : .white)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Capsule().fill(category == c ? .white : .white.opacity(0.14)))
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(FilterLooks.looks(in: category)) { l in
                        lookBubble(l)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
        .padding(.bottom, 4)
    }

    private func lookBubble(_ l: Look) -> some View {
        Button { look = l } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(look == l ? 0.28 : 0.12))
                        .frame(width: 54, height: 54)
                    Image(systemName: l.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(look == l ? Theme.accent : .white)
                }
                .overlay(Circle().strokeBorder(look == l ? Theme.accent : .clear, lineWidth: 2))
                Text(l.name)
                    .font(.label(9)).tracking(0.3)
                    .foregroundStyle(look == l ? .white : .white.opacity(0.65))
                    .lineLimit(1)
                    .frame(width: 62)
            }
        }
    }

    private var recordRow: some View {
        ZStack {
            Button(action: recordTapped) {
                ZStack {
                    Circle().strokeBorder(.white.opacity(0.9), lineWidth: 4)
                        .frame(width: 74, height: 74)
                    RoundedRectangle(cornerRadius: recording ? 7 : 30)
                        .fill(Color(red: 1, green: 0.27, blue: 0.27))
                        .frame(width: recording ? 30 : 60, height: recording ? 30 : 60)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: recording)
                }
            }
            .pressable()
            .disabled(countdown != nil)
        }
        .padding(.bottom, 26)
        .padding(.top, 4)
    }

    // MARK: camera + looks plumbing

    private func startCamera() {
        CameraCapture.requestAuthorization { result in
            switch result {
            case .failure(let e):
                errorText = e.errorDescription
            case .success:
                let c = CameraCapture(engine: engine)
                c.matteEnabled = lookUsesMatte
                do {
                    try c.start(position: position)
                    camera = c
                    pushLive()
                } catch {
                    errorText = error.localizedDescription
                }
            }
        }
    }

    private func flipCamera() {
        position = (position == .front) ? .back : .front
        do { try camera?.start(position: position); haptic() }
        catch { errorText = error.localizedDescription }
    }

    private var lookUsesMatte: Bool { look.stack.contains { $0.fx == "body_fx" } }

    /// Record-scoped live stack: no start/end → always on for the camera frame.
    private func pushLive() {
        engine.send("set_live_fx", ["fx": FilterLooks.liveStack(for: look, intensity: intensity)])
        camera?.matteEnabled = lookUsesMatte
    }

    private func recordTapped() {
        if recording { stopRecording(); return }
        if timerArmed { runCountdown(3) } else { startRecording() }
    }

    private func runCountdown(_ n: Int) {
        guard n > 0 else {
            withAnimation { countdown = nil }
            startRecording()
            return
        }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { countdown = n }
        haptic()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { runCountdown(n - 1) }
    }

    private func startRecording() {
        guard let camera else { return }
        let url = ProjectStore.mediaDir(model.project.id)
            .appendingPathComponent("take-\(Int(Date().timeIntervalSince1970)).mov")
        do {
            try camera.startTake(to: url)
            recordStart = Date(); elapsed = 0
            recording = true
            haptic()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func stopRecording() {
        recording = false
        recordStart = nil
        let entries = FilterLooks.brickEntries(for: look, intensity: intensity)
        camera?.stopTake { url in
            guard let url else {
                errorText = "Take failed to write."
                return
            }
            model.placeRecordedTake(url.path, look: entries)
            haptic()
        }
    }

    private func dismiss() {
        withAnimation { isPresented = false }
    }

    private func teardown() {
        if recording { camera?.stopTake { _ in } }
        camera?.stop()
        camera = nil
        model.syncLiveFX()   // restore the timeline-derived stack
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }

    private func haptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
