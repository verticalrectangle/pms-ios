//  InspectorView.swift
//  Selected-brick inspector — sits above the dock. Shows the brick's scope, its
//  Multi-FX chain, and live parameter sliders (each edit → set_clip_fx). Chains
//  can be decoupled (decouple_fx_brick); any brick can be deleted.

import SwiftUI

struct InspectorView: View {
    @ObservedObject var model: EditorModel
    let brickID: String

    private var sel: (track: Track, brick: Brick)? { model.selection() }

    var body: some View {
        if let sel, let bind = model.binding(forBrick: brickID) {
            let brick = sel.brick
            VStack(alignment: .leading, spacing: 11) {
                header(brick)
                scopeRow(brick)
                if brick.isChain { chainRow(brick) }
                paramSliders(brick, bind: bind)
                actions(brick)
            }
            .padding(14)
            .glass(18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear { model.loadBodyEffects() }   // body sliders need the defs
        }
    }

    private func header(_ brick: Brick) -> some View {
        HStack(spacing: 10) {
            Image(systemName: brick.kind == .bodyFX ? "person.fill" : brick.kind == .audioFX ? "waveform" : brick.isChain ? "square.3.layers.3d" : "sparkle")
                .font(.system(size: 16)).foregroundStyle(accentColor(brick))
                .frame(width: 30, height: 30)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(accentColor(brick).opacity(0.6)))
            VStack(alignment: .leading, spacing: 1) {
                Text(brick.isChain ? "\(brick.chain.count) FX CHAIN" : brick.title.uppercased())
                    .font(.disp(13)).foregroundStyle(.white).lineLimit(1)
                Text("\(fullTC(brick.start)) → \(fullTC(brick.end)) · \(String(format: "%.1f", brick.duration))s")
                    .font(.num(11.5)).foregroundStyle(Theme.txtMuted)
            }
            Spacer()
            ItemActionsMenu(model: model, id: brick.id)
            Button { model.selectedID = nil } label: {
                Image(systemName: "xmark").font(.system(size: 14)).foregroundStyle(Theme.txtMuted)
                    .frame(width: 30, height: 30)
            }
        }
    }

    private func scopeRow(_ brick: Brick) -> some View {
        let (text, color) = scope(brick)
        return HStack(spacing: 7) {
            Image(systemName: brick.kind == .glassFX || brick.kind == .multiFX ? "eye" : "square.3.layers.3d")
                .font(.system(size: 13)).foregroundStyle(color)
            Text(text).font(.label(9)).tracking(0.8).foregroundStyle(color)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(color.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(color.opacity(0.4)))
    }

    private func chainRow(_ brick: Brick) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(brick.chain.enumerated()), id: \.offset) { i, id in
                    HStack(spacing: 5) {
                        Text("\(i + 1)").font(.num(9)).foregroundStyle(Theme.txtGhost)
                        Text((EffectCatalog.byID[id]?.name ?? id).uppercased()).font(.label(8.5)).tracking(0.4)
                            .foregroundStyle(Theme.txtBody)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.line))
                    if i < brick.chain.count - 1 {
                        Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(Theme.txtGhost)
                    }
                }
            }
        }
    }

    /// Slider defs for this brick. Body bricks come from the engine's
    /// list_body_fx (positional keys body_fx_param_i + body_fx_amount);
    /// everything else from the generated catalog by effect id.
    private func paramDefs(_ brick: Brick) -> [EffectDef.Param] {
        if brick.kind == .bodyFX {
            guard let def = model.bodyDef(named: brick.bodyFXType) else { return [] }
            var ps = def.params.enumerated().map { i, p in
                EffectDef.Param(key: "body_fx_param_\(i)", label: p.label,
                                min: p.min, max: p.max, def: p.def, format: p.format)
            }
            ps.append(.init(key: "body_fx_amount", label: "Amount",
                            min: 0, max: 1, def: 1, format: "%.2f"))
            return ps
        }
        return EffectCatalog.byID[brick.chain.last ?? ""]?.params ?? []
    }

    private func paramSliders(_ brick: Brick, bind: Binding<Brick>) -> some View {
        VStack(spacing: 9) {
            ForEach(paramDefs(brick), id: \.key) { p in
                let value = Binding<Double>(
                    get: { bind.wrappedValue.params[p.key] ?? p.def },
                    set: { model.setParam(p.key, $0, onBrick: brick.id) }
                )
                VStack(spacing: 2) {
                    HStack {
                        Text(p.label.uppercased())
                            .font(.label(8.5)).tracking(0.8).foregroundStyle(Theme.txtMuted)
                        Spacer()
                        Text(String(format: "%.2f", value.wrappedValue)).font(.num(10)).foregroundStyle(Theme.accent)
                    }
                    Slider(value: value, in: p.min...p.max).tint(Theme.accent)
                }
            }
        }
    }

    private func actions(_ brick: Brick) -> some View {
        HStack(spacing: 7) {
            if brick.coupled {
                inspectorButton("Decouple", tint: Theme.txt) { model.decouple(brick.id) }
            }
            inspectorButton("Add FX", tint: Theme.txt) { model.activeSheet = .fx }
            inspectorButton("Split", tint: Theme.txt) { model.splitAtPlayhead() }
                .disabled(!(model.playhead > brick.start + 0.1 && model.playhead < brick.end - 0.1))
            inspectorButton("Delete", tint: Color(red: 1, green: 0.55, blue: 0.55)) { model.deleteBrick(brick.id) }
        }
    }

    private func inspectorButton(_ label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.label(10)).tracking(0.6).foregroundStyle(tint)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.35)))
        }
    }

    private func accentColor(_ b: Brick) -> Color {
        switch b.kind { case .glassFX, .multiFX: Theme.glassCyan; case .bodyFX: Theme.bodyViolet
        case .globalFX: Theme.accent; case .audioFX: Theme.txt }
    }

    private func scope(_ b: Brick) -> (String, Color) {
        switch b.kind {
        case .glassFX, .multiFX: ("GLASS · pre-composite · clip-bound", Theme.glassCyan)
        case .globalFX:          ("GLOBAL · post-composite · all below", Theme.accent)
        case .bodyFX:            ("BODY FX · silhouette · masks", Theme.bodyViolet)
        case .audioFX:           ("AUDIO · live chain · welded", Theme.accent)
        }
    }
}
