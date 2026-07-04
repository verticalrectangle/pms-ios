//  FXSheet.swift
//  Effect browser. Three tabs map to the three brick levers: Video (add_effect_brick),
//  Body (add_body_fx_brick / remove_background), Audio (add_audio_multifx_brick).
//  Pick a placement — Glass (onto the selected clip) or Global (onto the FX rail) —
//  then tap an effect to drop it. Tapping an already-selected brick welds a chain.

import SwiftUI

struct FXSheet: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable { case video = "Video FX", body = "Body FX", audio = "Audio FX" }
    @State private var tab: Tab = .video
    @State private var category = "All"
    @State private var query = ""
    @State private var placeGlobal = false

    private var source: [EffectDef] {
        switch tab { case .video: Effects.video; case .body: Effects.body; case .audio: Effects.audio }
    }
    private var list: [EffectDef] {
        source.filter {
            (tab != .video || category == "All" || $0.category == category) &&
            (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        GlassSheet(title: "Effects", eyebrow: "\(Effects.all.count) GPU EFFECTS · HOT-RELOADED", full: true) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)

                placementNote

                if tab == .video {
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.txtMuted)
                        TextField("Search effects…", text: $query)
                            .foregroundStyle(Theme.txt).font(.system(size: 14))
                    }
                    .padding(.horizontal, 13).padding(.vertical, 10).glass(13, flat: true)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(Effects.categories, id: \.self) { c in
                                Chip(text: c, on: category == c) { category = c }
                            }
                        }
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(list) { effect in
                        Button { place(effect) } label: { EffectCard(effect: effect) }.pressable()
                    }
                }
            }
        }
    }

    private var placementNote: some View {
        Group {
            if tab == .video {
                Picker("", selection: $placeGlobal) {
                    Text("Glass · selected clip").tag(false)
                    Text("Global · rail").tag(true)
                }.pickerStyle(.segmented)
            } else if tab == .body {
                Label("Silhouette FX — runs process_body_fx_masks on the clip below", systemImage: "person.fill")
                    .font(.label(9)).tracking(0.4).foregroundStyle(Theme.bodyViolet)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bodyViolet.opacity(0.08)))
            } else {
                Label("LIVE audio chain — auto-welds to the audio clip (1.5s)", systemImage: "waveform")
                    .font(.label(9)).tracking(0.4).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentA(0.07)))
            }
        }
    }

    private func place(_ effect: EffectDef) {
        let t = model.playhead
        // weld into the currently selected brick if there is one
        if let sel = model.selectedID, model.selection() != nil {
            model.weld(effect.id, intoBrick: sel)
        } else {
            let firstVideoClip = model.tracks.first { $0.kind == .video }?.clips.first { t >= $0.start && t < $0.end }?.id
                ?? model.tracks.first { $0.kind == .video }?.clips.first?.id ?? "c1"
            let audioClip = model.tracks.first { $0.kind == .audio }?.clips.first?.id ?? "a1"
            let target: DropTarget
            switch tab {
            case .audio: target = .audioClip(audioClip)
            case .body:  target = .clip(firstVideoClip)
            case .video: target = placeGlobal ? .fxRail : .clip(firstVideoClip)
            }
            model.placeEffect(effect, onto: target, at: t)
        }
        dismiss()
    }
}

private struct EffectCard: View {
    let effect: EffectDef
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: "sparkle")
                    .font(.system(size: 18)).foregroundStyle(Theme.txt)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.03)))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.lineStrong))
                Spacer()
                Text(effect.category.uppercased()).font(.label(8)).tracking(1).foregroundStyle(Theme.txtGhost)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(effect.name).font(.disp(14)).textCase(.uppercase).foregroundStyle(.white)
                Text(effect.params.isEmpty ? "amount" : "\(effect.params.count) param\(effect.params.count == 1 ? "" : "s")")
                    .font(.num(12)).foregroundStyle(Theme.txtMuted)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .glass(Theme.rCard)
    }
}
