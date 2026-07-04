//  TransportBar.swift
//  Transport controls + master readouts (BPM from analyze_audio, LUFS from the
//  loudness event) and the bottom tool dock.

import SwiftUI

struct TransportBar: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var engine: EngineStore

    private var t: Double { engine.playing ? engine.playhead : model.localSeek }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                // Compact M:SS in the transport (frames live in the inspector /
                // fullscreen player where there's room) — the full MM:SS:FF is
                // ~95pt and overflowed the bar.
                Text(String(format: "%d:%02d", Int(t) / 60, Int(t) % 60))
                    .font(.num(17, .bold)).foregroundStyle(Theme.accent)
                    .shadow(color: Theme.accentA(0.5), radius: 4)
                Text("\(Int(model.bpm)) BPM").font(.label(8)).tracking(1.2).foregroundStyle(Theme.txtMuted)
            }
            .frame(width: 64, alignment: .leading)

            Spacer(minLength: 4)

            HStack(spacing: 12) {
                TransportButton(system: "gobackward.5", size: 20) { model.seek(t - 5) }
                Button { model.togglePlay() } label: {
                    Image(systemName: engine.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 22)).foregroundStyle(engine.playing ? Theme.accent : Theme.txt)
                        .frame(width: 56, height: 56).glass(28, active: engine.playing)
                }.pressable()
                TransportButton(system: "goforward.5", size: 20) { model.seek(t + 5) }
            }

            Spacer(minLength: 4)

            LufsMeter(lufs: engine.masterLufs)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 4)
    }
}

private struct TransportButton: View {
    let system: String; let size: CGFloat; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: size)).foregroundStyle(Theme.txt)
                .frame(width: 44, height: 44).glass(22)
        }.pressable()
    }
}

/// Compact master loudness meter. Reads the `loudness` event (momentary, integrated).
private struct LufsMeter: View {
    let lufs: (momentary: Double, integrated: Double)?

    // map -30…0 LUFS → 0…1
    private func norm(_ v: Double) -> Double { min(1, max(0, (v + 30) / 30)) }

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 3) {
                ForEach(0..<10) { i in
                    let lit = lufs.map { norm($0.momentary) * 10 > Double(i) } ?? false
                    let hot = i >= 8
                    RoundedRectangle(cornerRadius: 1)
                        .fill(lit ? (hot ? Color(red: 1, green: 0.5, blue: 0.5) : Theme.accent) : Theme.line)
                        .frame(width: 4, height: 6 + CGFloat(i))
                }
            }
            .frame(height: 16, alignment: .bottom)
            Text(lufs.map { String(format: "%.1f LUFS", $0.integrated) } ?? "— LUFS")
                .font(.num(9)).foregroundStyle(Theme.txtMuted)
        }
    }
}

// MARK: - Tool dock

struct ToolDock: View {
    @ObservedObject var model: EditorModel

    private let items: [(EditorSheet, String, String)] = [
        (.media,  "square.stack",       "Media"),
        (.fx,     "sparkles",           "FX"),
        (.lyrics, "textformat",         "Text"),
        (.agent,  "brain.head.profile", "Agent"),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.0) { item in
                let on = model.activeSheet == item.0
                Button {
                    model.activeSheet = (model.activeSheet == item.0) ? nil : item.0
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.1).font(.system(size: 20))
                        Text(item.2).font(.label(8.5)).tracking(1)
                    }
                    .foregroundStyle(on ? Theme.accent : Theme.txtBody)
                    .frame(minWidth: 56).padding(.vertical, 6).padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(on ? Theme.accentA(0.12) : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(on ? Theme.accentA(0.4) : .clear, lineWidth: 1))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(7)
        .glass(999)
    }
}

// MARK: - Global busy / pipeline bar (the `busy` event: label + progress)

struct BusyBar: View {
    let busy: (label: String, progress: Double)?
    var body: some View {
        if let busy {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small).tint(Theme.accent)
                Text(busy.label.uppercased()).font(.label(9)).tracking(1).foregroundStyle(Theme.accent)
                Spacer()
                Text("\(Int(busy.progress * 100))%").font(.num(11)).foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .glass(14, active: true)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
