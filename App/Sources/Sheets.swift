//  Sheets.swift
//  Bottom-sheet surfaces: a shared GlassSheet chrome + the Agent (on-device AI
//  actions + chat), Media bin, Lyric styling, and Export sheets. Each action maps
//  to a real lever from LEVERS.md.

import SwiftUI

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
                        if let eyebrow { Text(eyebrow).font(.label(9)).tracking(2).foregroundStyle(Theme.accent) }
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

// MARK: - Agent (AI actions + chat)

struct AgentSheet: View {
    @ObservedObject var model: EditorModel
    var body: some View {
        GlassSheet(title: "Agent", eyebrow: "MCP · 83 LEVERS · ON-DEVICE", full: true) {
            VStack(alignment: .leading, spacing: 16) {
                Text("On-device actions").font(.label(9)).tracking(2).foregroundStyle(Theme.txtMuted)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(AIActions.all) { action in
                        Button { model.run(action) } label: { AIActionCard(action: action) }.pressable()
                    }
                }
                Text("Transcript").font(.label(9)).tracking(2).foregroundStyle(Theme.txtMuted)
                ChatTranscript()
            }
        }
    }
}

private struct AIActionCard: View {
    let action: AIAction
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: action.icon).font(.system(size: 18)).foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(Theme.accentA(0.1)))
            VStack(alignment: .leading, spacing: 1) {
                Text(action.title).font(.disp(13)).textCase(.uppercase).foregroundStyle(.white)
                Text(action.model).font(.num(11)).foregroundStyle(Theme.txtMuted).lineLimit(1)
            }
            Text(action.lever + "()").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.accentA(0.7))
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .glass(Theme.rCard)
    }
}

private struct ChatTranscript: View {
    // real levers in the tool calls
    private let lines: [(String, String, String)] = [
        ("user", "", "find the drop and add a glitch right before it"),
        ("tool", "find_audio_cue", "onset @ 13.4s · drop"),
        ("ai", "", "Found the drop at 13.4s. Dropping a Glitch Block on the FX rail from 12.9–13.4."),
        ("tool", "add_effect_brick", "GFX · glitch_block · 12.9→13.4"),
        ("user", "", "make the lyrics lavender and typewriter them in"),
        ("tool", "set_typography_preset", "preset=LAVENDER"),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, m in
                switch m.0 {
                case "user":
                    Text(m.2).font(.system(size: 14)).foregroundStyle(Theme.txt)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .glass(14).frame(maxWidth: .infinity, alignment: .trailing)
                case "ai":
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "circle.hexagongrid").foregroundStyle(Theme.accent)
                        Text(m.2).font(.system(size: 14)).foregroundStyle(Theme.txtBody)
                    }
                default:
                    HStack(spacing: 8) {
                        Image(systemName: "terminal").font(.system(size: 13)).foregroundStyle(Theme.accent)
                        Text(m.1 + "()").font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.accent)
                        Text("· " + m.2).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.txtMuted)
                    }
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glass(10, flat: true)
                }
            }
        }
    }
}

// MARK: - Media bin

struct MediaSheet: View {
    private let items: [(String, String, Int, String?)] = [
        ("EYE_CLOSEUP", "0:06", 1, "eyecl"), ("OCEAN_4K", "0:24", 1, "ocean4k"),
        ("NEON_RUN", "0:12", 2, "neonrun"), ("CITY_NIGHT", "1:02", 0, "citynight"),
        ("STATIC_BG", "0:30", 0, "staticbg"), ("HANDS_CLOSEUP", "0:08", 0, "handsclose"),
        ("glass_drown.wav", "0:18", 1, nil), ("vocals_dry.wav", "0:18", 0, nil),
    ]
    var body: some View {
        GlassSheet(title: "Project Bin", eyebrow: "MEDIA LIBRARY · \(items.count) ITEMS", full: true) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)], spacing: 11) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                    VStack(spacing: 8) {
                        ZStack {
                            if let seed = it.3 {
                                AsyncImage(url: URL(string: "https://picsum.photos/seed/\(seed)/240/150")) { $0.resizable().scaledToFill() } placeholder: { Theme.line }
                            } else {
                                Image(systemName: "waveform").font(.system(size: 24)).foregroundStyle(Theme.txtMuted)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color.white.opacity(0.03))
                            }
                        }
                        .frame(height: 78).clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay(alignment: .topLeading) { if it.2 > 0 { Text("×\(it.2)").font(.num(11)).foregroundStyle(Theme.accent).padding(5) } }
                        .overlay(alignment: .bottomTrailing) { Text(it.1).font(.num(11)).foregroundStyle(.white).shadow(color: .black, radius: 2).padding(5) }
                        HStack {
                            Text(it.0).font(.label(10)).tracking(0.4).foregroundStyle(Theme.txt).lineLimit(1)
                            Spacer()
                            Image(systemName: "plus").font(.system(size: 13)).foregroundStyle(Theme.txtMuted)
                        }
                    }
                    .padding(8).glass(15)
                }
            }
        }
    }
}

// MARK: - Lyric styling (managed Lyrics track from trigger_pipeline)

struct LyricsSheet: View {
    @ObservedObject var model: EditorModel
    @State private var preset = "LAVENDER"
    private let presets: [(String, Color?)] = [("NEON", Color(red: 1, green: 0.35, blue: 0.63)), ("CYBER", Color(red: 0.25, green: 0.88, blue: 0.88)), ("LAVENDER", Theme.accent), ("CLEAN", nil)]
    private let anims = ["Fade", "Glitch", "Typewriter", "Bounce", "Scale", "Slide"]

    var body: some View {
        GlassSheet(title: "Lyric Style", eyebrow: "WORD-LEVEL · CTC ALIGNED", full: true) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.accent)
                    Text("Pipeline ready · MDX-Net stems · transcript aligned").font(.label(9)).tracking(0.6).foregroundStyle(Theme.txtBody)
                    Spacer()
                    Button { model.engine.command("trigger_pipeline"); model.engine.simulateBusy(label: "Separating stems…") } label: {
                        Text("Re-run").font(.label(9)).tracking(1).foregroundStyle(Theme.accent)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .overlay(Capsule().strokeBorder(Theme.accentA(0.5)))
                    }
                }
                .padding(11).glass(12, flat: true)

                Text("Typography preset").font(.label(9)).tracking(2).foregroundStyle(Theme.txtMuted)
                HStack(spacing: 8) {
                    ForEach(presets, id: \.0) { p in
                        Button {
                            preset = p.0
                            model.engine.command("set_typography_preset", ["preset": p.0])
                        } label: {
                            VStack(spacing: 6) {
                                Circle().fill(p.1 ?? .clear).frame(width: 16, height: 16)
                                    .overlay(Circle().strokeBorder(p.1 == nil ? Theme.lineStrong : .clear))
                                    .shadow(color: p.1 ?? .clear, radius: 5)
                                Text(p.0).font(.label(9)).tracking(0.4).foregroundStyle(.white)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .glass(12, active: preset == p.0)
                        }
                    }
                }

                Text("Animation").font(.label(9)).tracking(2).foregroundStyle(Theme.txtMuted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) { ForEach(anims, id: \.self) { Chip(text: $0, on: $0 == "Typewriter") {} } }
                }
            }
        }
    }
}

// MARK: - Export (trigger_export → get_export_status)

struct ExportSheet: View {
    @ObservedObject var model: EditorModel
    @State private var format: Format
    @State private var phase: Phase = .idle
    @State private var pct = 0.0
    enum Phase { case idle, rendering, done }

    init(model: EditorModel) { self.model = model; _format = State(initialValue: model.format) }

    var body: some View {
        GlassSheet(title: "Export", eyebrow: "GL FBO → H.264 / AAC · PIXEL-IDENTICAL") {
            VStack(spacing: 12) {
                ForEach(Format.allCases, id: \.self) { f in
                    Button { if phase == .idle { format = f; model.engine.command("set_format", ["preset": f.lever]) } } label: {
                        HStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(format == f ? Theme.accent : Theme.lineHover, lineWidth: 1.5)
                                .frame(width: f == .landscape ? 46 : f == .square ? 36 : 26, height: f == .landscape ? 26 : 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.rawValue).font(.disp(19)).foregroundStyle(format == f ? Theme.accent : Theme.txt)
                                Text("\(f.resolution) · \(f.platform)").font(.num(12)).foregroundStyle(Theme.txtMuted)
                            }
                            Spacer()
                            if format == f { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                        }
                        .padding(14).frame(maxWidth: .infinity).glass(15, active: format == f)
                    }
                }

                switch phase {
                case .idle:
                    Button { startRender() } label: {
                        HStack(spacing: 10) { Image(systemName: "square.and.arrow.up"); Text("Render \(format.rawValue)").font(.disp(16)) }
                            .foregroundStyle(Theme.accent).frame(maxWidth: .infinity).padding(.vertical, 15).glass(15, active: true)
                    }
                case .rendering:
                    VStack(alignment: .leading, spacing: 9) {
                        HStack { Text("RENDERING…").font(.label(10)).foregroundStyle(Theme.accent); Spacer(); Text("\(Int(pct * 100))%").font(.num(13)).foregroundStyle(Theme.accent) }
                        ProgressView(value: pct).tint(Theme.accent)
                        Text("frame \(Int(pct * 540))/540 · same GL pipeline as preview").font(.num(12)).foregroundStyle(Theme.txtMuted)
                    }.padding(16).glass(15, flat: true)
                case .done:
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle").font(.system(size: 34)).foregroundStyle(Theme.accent)
                        Text("Render complete").font(.disp(18)).foregroundStyle(.white)
                        Text("GLASS_DROWN_\(format.rawValue.replacingOccurrences(of: ":", with: "x")).MP4 · 14.2 MB").font(.num(12)).foregroundStyle(Theme.txtMuted)
                    }.padding(18).frame(maxWidth: .infinity).glass(15)
                }
            }
        }
    }

    private func startRender() {
        model.engine.command("trigger_export", ["format": format.lever])
        phase = .rendering; pct = 0
        Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { tm in
            pct += 0.02
            if pct >= 1 { pct = 1; phase = .done; tm.invalidate() }
        }
    }
}
