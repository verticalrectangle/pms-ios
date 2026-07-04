//  TransportBar.swift
//  Transport controls + master readouts (BPM from analyze_audio, LUFS from the
//  loudness event) and the bottom tool dock.

import SwiftUI

struct TransportBar: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var engine: EngineStore

    private var t: Double { model.playhead }

    var body: some View {
        // Buttons are always perfectly centred (ZStack center); the readouts
        // are pinned to the edges by an overlaid HStack so they take their
        // natural width without pushing the bar wider than the screen.
        ZStack {
            HStack(spacing: 12) {
                TransportButton(system: "gobackward.5", size: 20) { model.seek(t - 5) }
                Button { model.togglePlay() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22)).foregroundStyle(model.isPlaying ? Theme.accent : Theme.txt)
                        .frame(width: 56, height: 56).glass(28, active: model.isPlaying)
                }.pressable()
                TransportButton(system: "goforward.5", size: 20) { model.seek(t + 5) }
            }

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(format: "%d:%02d", Int(t) / 60, Int(t) % 60))
                        .font(.num(17, .bold)).foregroundStyle(Theme.accent)
                        .shadow(color: Theme.accentA(0.5), radius: 4)
                    Text("\(Int(model.bpm)) BPM").font(.label(8)).foregroundStyle(Theme.txtMuted)
                }
                .fixedSize()
                Spacer(minLength: 8)
                LufsMeter(lufs: engine.masterLufs).fixedSize()
            }
        }
        .padding(.horizontal, 8)
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
                        Text(item.2).font(.label(8.5))
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
                Text(busy.label.uppercased()).font(.label(9)).foregroundStyle(Theme.accent)
                Spacer()
                Text("\(Int(busy.progress * 100))%").font(.num(11)).foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .glass(14, active: true)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
