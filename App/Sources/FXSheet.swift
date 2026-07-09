//  FXSheet.swift
//  Effect browser over the FULL generated catalog (GeneratedEffectCatalog.swift,
//  regenerated from the desktop registry). Video FX place through
//  add_effect_brick (Glass = onto the selected/overlapped clip's track, which
//  auto-couples engine-side; Global = the GFX rail); audio FX through
//  add_audio_multifx_brick. Placement is disabled when there is no valid host —
//  never a made-up fallback id. Body FX are hidden until the engine exposes a
//  BodyFX manifest/query.

import SwiftUI

struct FXSheet: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable { case video = "Video FX", body = "Body FX", audio = "Audio FX" }
    @State private var tab: Tab = .video
    @State private var category = "All"
    @State private var query = ""
    @State private var placeGlobal = false
    @State private var placeError: String?

    private var source: [EffectDef] {
        switch tab { case .video: EffectCatalog.video; case .audio: EffectCatalog.audio; case .body: [] }
    }
    private var list: [EffectDef] {
        source.filter {
            (tab != .video || category == "All" || $0.category == category) &&
            (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query))
        }
    }

    /// The video clip under the playhead (falling back to the first video clip)
    /// — the host a Glass placement rides on. nil = no valid host.
    private var videoHostClipID: String? {
        let t = model.playhead
        let clips = model.tracks.first { $0.kind == .video }?.clips ?? []
        return (clips.first { t >= $0.start && t < $0.end } ?? clips.last)?.id
    }
    private var audioHostClipID: String? {
        // Audio FX chains couple to audio content; video clips carry audio too.
        let clips = (model.tracks.first { $0.kind == .audio }?.clips)
            ?? (model.tracks.first { $0.kind == .video }?.clips) ?? []
        return clips.first?.id
    }

    private var canPlace: Bool {
        switch tab {
        case .video: return placeGlobal || videoHostClipID != nil
        case .body:  return videoHostClipID != nil
        case .audio: return audioHostClipID != nil
        }
    }

    var body: some View {
        GlassSheet(title: "Effects", eyebrow: "\(EffectCatalog.all.count) ENGINE EFFECTS", full: true) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)

                placementNote

                if let placeError {
                    Label(placeError, systemImage: "exclamationmark.triangle")
                        .font(.label(9)).tracking(0.4).foregroundStyle(Color(red: 1, green: 0.6, blue: 0.5))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.08)))
                }

                if tab == .video {
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.txtMuted)
                        TextField("Search effects…", text: $query)
                            .foregroundStyle(Theme.txt).font(.system(size: 14))
                    }
                    .padding(.horizontal, 13).padding(.vertical, 10).glass(13, flat: true)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(["All"] + EffectCatalog.videoCategories, id: \.self) { c in
                                Chip(text: c, on: category == c) { category = c }
                            }
                        }
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    if tab == .body {
                        ForEach(model.bodyEffects) { def in
                            Button { placeBody(def) } label: { BodyEffectCard(def: def) }
                                .pressable()
                                .disabled(!canPlace)
                                .opacity(canPlace ? 1 : 0.4)
                        }
                    } else {
                        ForEach(list) { effect in
                            Button { place(effect) } label: { EffectCard(effect: effect) }
                                .pressable()
                                .disabled(!canPlace)
                                .opacity(canPlace ? 1 : 0.4)
                        }
                    }
                }
            }
        }
        .onAppear { model.loadBodyEffects() }
    }

    private func placeBody(_ def: BodyFXDef) {
        placeError = nil
        if model.placeBodyEffect(def, at: model.playhead) { dismiss() }
        else { placeError = model.engine.lastError ?? "The engine rejected that placement." }
    }

    private var placementNote: some View {
        Group {
            if tab == .video {
                VStack(spacing: 6) {
                    Picker("", selection: $placeGlobal) {
                        Text("Glass · selected clip").tag(false)
                        Text("Global · rail").tag(true)
                    }.pickerStyle(.segmented)
                    if !placeGlobal && videoHostClipID == nil {
                        Label("Import a video clip first — Glass FX ride on a clip", systemImage: "film")
                            .font(.label(9)).tracking(0.4).foregroundStyle(Theme.txtMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else if tab == .body {
                if model.bodyEffects.isEmpty {
                    Label("Body FX list unavailable — engine query failed", systemImage: "person.slash")
                        .font(.label(9)).tracking(0.4).foregroundStyle(Theme.txtMuted)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bodyViolet.opacity(0.08)))
                } else {
                    Label(videoHostClipID == nil
                          ? "Import a video clip first — body FX ride on a clip"
                          : "Silhouette FX — live person matte (Vision)", systemImage: "person.fill")
                        .font(.label(9)).tracking(0.4).foregroundStyle(Theme.bodyViolet)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bodyViolet.opacity(0.08)))
                }
            } else {
                if audioHostClipID == nil {
                    Label("Import audio or video first — audio FX weld to a clip", systemImage: "waveform")
                        .font(.label(9)).tracking(0.4).foregroundStyle(Theme.txtMuted)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentA(0.07)))
                } else {
                    Label("LIVE audio chain — auto-welds to the audio clip", systemImage: "waveform")
                        .font(.label(9)).tracking(0.4).foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentA(0.07)))
                }
            }
        }
    }

    private func place(_ effect: EffectDef) {
        placeError = nil
        let t = model.playhead
        let placed: Bool
        // Weld into the currently selected brick if there is one.
        if let sel = model.selectedID, model.selection() != nil, tab == .video {
            model.weld(effect.id, intoBrick: sel)
            placed = true
        } else {
            let target: DropTarget
            switch tab {
            case .body:
                return   // body placement routes through placeBody()
            case .audio:
                guard let host = audioHostClipID else { return }
                target = .audioClip(host)
            case .video:
                if placeGlobal { target = .fxRail }
                else {
                    guard let host = videoHostClipID else { return }
                    target = .clip(host)
                }
            }
            placed = model.placeEffect(effect, onto: target, at: t)
        }
        // Dismiss only on real engine success; otherwise show the handler error.
        if placed { dismiss() }
        else { placeError = model.engine.lastError ?? "The engine rejected that placement." }
    }
}

private struct BodyEffectCard: View {
    let def: BodyFXDef
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: "person.fill")
                    .font(.system(size: 18)).foregroundStyle(Theme.bodyViolet)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.bodyViolet.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.bodyViolet.opacity(0.4)))
                Spacer()
                Text(def.category.uppercased()).font(.label(8)).foregroundStyle(Theme.txtGhost)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(def.name).font(.disp(14)).textCase(.uppercase).foregroundStyle(.white)
                Text(def.tagline.isEmpty ? "\(def.params.count) params" : def.tagline)
                    .font(.num(11)).foregroundStyle(Theme.txtMuted).lineLimit(1)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .glass(Theme.rCard)
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
                Text(effect.category.uppercased()).font(.label(8)).foregroundStyle(Theme.txtGhost)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(effect.name).font(.disp(14)).textCase(.uppercase).foregroundStyle(.white)
                Text(effect.params.isEmpty ? "no params" : "\(effect.params.count) param\(effect.params.count == 1 ? "" : "s")")
                    .font(.num(12)).foregroundStyle(Theme.txtMuted)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .glass(Theme.rCard)
    }
}
