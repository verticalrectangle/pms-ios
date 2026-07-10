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
    // Chroma key override: nil = matte mode (background trails behind you);
    // set = colour key sampled by tapping the preview. Double-tap resets.
    @State private var keyOverride: (r: Double, g: Double, b: Double)?
    @State private var keyHint: String?
    // Makeup Studio: a non-nil spec overrides the active look's face entry
    // (live-editable); saved specs join the rail as custom looks.
    @State private var showStudio = false
    @State private var studioSpec = MakeupSpec()
    @State private var studioActive = false
    @State private var customLooks: [SavedLook] = CustomLookStore.load()
    // WYSIWYG take encoder — looks are baked into the recorded pixels.
    @State private var recorder: FilteredTakeRecorder?

    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                MetalPreview(store: engine)
                    .aspectRatio(model.format.aspect, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        guard lookHasChroma else { return }
                        keyOverride = nil
                        keyHint = "Keying on you — background reacts"
                        pushLive(); haptic()
                    }
                    .onTapGesture { location in
                        pickKey(at: location, in: geo.size)
                    }
            }

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
                if let keyHint {
                    Text(keyHint)
                        .font(.label(11)).foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(.black.opacity(0.4)))
                        .padding(.top, 6)
                        .transition(.opacity)
                        .task { try? await Task.sleep(nanoseconds: 2_200_000_000)
                                withAnimation { self.keyHint = nil } }
                }
                Spacer()
                if look != .none && !recording { intensityRow }
                lookRail
                recordRow
            }
        }
        .statusBarHidden()
        .onAppear { claimFramePath(); startCamera() }
        .onDisappear(perform: teardown)
        .onReceive(ticker) { _ in
            if let s = recordStart { elapsed = Date().timeIntervalSince(s) }
        }
        .onChange(of: look) { _, _ in
            keyOverride = nil
            studioActive = false
            if let e = look.stack.first(where: { $0.fx == "face_fx" }) {
                studioSpec = MakeupSpec(fromLookEntry: e.params, makeupTex: e.makeupTex)
            }
            if lookHasChroma { keyHint = "Background reacts around you — tap a color to key it instead" }
            pushLive(); haptic()
        }
        .onChange(of: intensity) { _, _ in pushLive() }
        .sheet(isPresented: $showStudio) {
            MakeupStudioSheet(spec: $studioSpec,
                              onChange: { studioActive = true; pushLive() },
                              onSave: { name, spec in
                                  let saved = CustomLookStore.add(name: name, spec: spec)
                                  customLooks = CustomLookStore.load()
                                  look = saved.asLook
                              })
        }
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
            if lookUsesFace {
                // Makeup Studio: edit this look's morphs/makeup live, save yours.
                Button { showStudio = true; haptic() } label: {
                    Image(systemName: "slider.horizontal.2.square.on.square")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(studioActive ? Theme.accent : .white)
                        .padding(8)
                        .background(Circle().fill(.black.opacity(0.35)))
                }
            }
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
                    ForEach(railLooks) { l in
                        lookBubble(l)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
        .padding(.bottom, 4)
    }

    /// Preset looks for the category + the user's saved Studio looks (Makeup).
    private var railLooks: [Look] {
        var looks = FilterLooks.looks(in: category)
        if category == .makeup || category == .forYou {
            looks += customLooks.map(\.asLook)
        }
        return looks
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

    /// The engine renders the scene compositor whenever ANY layer frame is
    /// stored — stale timeline frames would shadow the live camera and mute
    /// set_live_fx. Record mode owns the frame path: pause playback, suspend
    /// the feeder + timeline-driven live-FX pushes, drop the layer store.
    private func claimFramePath() {
        if model.isPlaying { model.togglePlay() }
        model.liveFXSuspended = true
        model.layers?.suspended = true
        engine.send("clear_layer_frames")
    }

    private var lookHasChroma: Bool {
        look.stack.contains { $0.fx.hasPrefix("chroma_") }
    }

    /// Tap-to-pick chroma key: map the tap through the aspect-fit preview
    /// rect to buffer UVs and sample the live camera frame. (The canvas and
    /// the camera are both aspect-fit; for the 9:16-on-9:16 record case the
    /// mapping is exact, and for other formats it's within the letterbox.)
    private func pickKey(at location: CGPoint, in size: CGSize) {
        guard lookHasChroma, let camera else { return }
        let aspect = CGFloat(model.format.aspect)
        var fit = CGRect(origin: .zero, size: size)
        if size.width / size.height > aspect {   // pillarbox
            let w = size.height * aspect
            fit = CGRect(x: (size.width - w) / 2, y: 0, width: w, height: size.height)
        } else {                                  // letterbox
            let h = size.width / aspect
            fit = CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h)
        }
        guard fit.contains(location) else { return }
        let u = (location.x - fit.minX) / fit.width
        let v = (location.y - fit.minY) / fit.height
        guard let c = camera.sampleColor(atNormalized: CGPoint(x: u, y: v)) else { return }
        keyOverride = c
        keyHint = "Keying on tapped color — double-tap to key on you"
        pushLive(); haptic()
    }

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

    private var lookUsesMatte: Bool {
        look.stack.contains { $0.fx == "body_fx" } ||
        (lookHasChroma && keyOverride == nil)   // matte-keyed chroma (selfie mode)
    }

    private var lookUsesFace: Bool {
        look.stack.contains { $0.fx == "face_fx" }
    }

    /// Record-scoped live stack: no start/end → always on for the camera
    /// frame. A tap-picked key overrides the chroma entries' matte mode; an
    /// active Studio spec overrides the look's face entry wholesale.
    private func pushLive() {
        var stack = FilterLooks.liveStack(for: look, intensity: intensity)
        if let k = keyOverride {
            stack = stack.map { e in
                guard let fx = e["fx_type"] as? String, fx.hasPrefix("chroma_"),
                      var p = e["params"] as? [String: Double] else { return e }
                p["matte_key"] = 0
                p["\(fx)_r"] = k.r; p["\(fx)_g"] = k.g; p["\(fx)_b"] = k.b
                var e = e; e["params"] = p; return e
            }
        }
        if studioActive, lookUsesFace {
            stack = stack.map { e in
                guard (e["fx_type"] as? String) == "face_fx" else { return e }
                var p = studioSpec.params
                p["face_amount"] = intensity
                var e: [String: Any] = ["fx_type": "face_fx", "params": p]
                if let tex = studioSpec.makeupTex { e["face_makeup_tex"] = tex }
                return e
            }
        }
        engine.send("set_live_fx", ["fx": stack])
        engine.send("face_track_enable", ["on": lookUsesFace])
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
        // WYSIWYG: every camera frame is re-rendered through the engine's
        // live-FX stack and encoded — the look is IN the recorded pixels
        // (makeup, matte trails, everything), exactly as previewed.
        guard let rec = FilteredTakeRecorder(engine: engine, url: url) else {
            errorText = "Take recorder failed to start."
            return
        }
        recorder = rec
        camera.filteredRecorder = rec
        recordStart = Date(); elapsed = 0
        recording = true
        haptic()
    }

    private func stopRecording() {
        recording = false
        recordStart = nil
        camera?.filteredRecorder = nil
        let rec = recorder
        recorder = nil
        rec?.finish { url in
            guard let url else {
                errorText = "Take failed to write."
                return
            }
            // The look is baked into the file — land it clean, no brick
            // (a timeline brick would double-apply the effect).
            model.placeRecordedTake(url.path, look: [])
            haptic()
        }
    }

    private func dismiss() {
        withAnimation { isPresented = false }
    }

    private func teardown() {
        camera?.filteredRecorder = nil
        recorder?.finish { _ in }
        recorder = nil
        camera?.stop()
        camera = nil
        engine.send("face_track_enable", ["on": false])
        // Hand the frame path back to the timeline: resume the feeder, restore
        // the timeline-derived stack, and nudge a seek so layers re-feed.
        model.liveFXSuspended = false
        model.layers?.suspended = false
        model.syncLiveFX()
        model.seek(model.playhead)
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }

    private func haptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
