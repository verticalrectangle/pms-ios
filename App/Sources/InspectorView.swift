//  InspectorView.swift
//  Selected-brick inspector — sits above the dock. Shows the brick's scope, its
//  Multi-FX chain, and live parameter sliders (each edit → set_clip_fx). Chains
//  can be decoupled (decouple_fx_brick); any brick can be deleted.

import SwiftUI
import UIKit

struct InspectorView: View {
    @ObservedObject var model: EditorModel
    let brickID: String

    private var sel: (track: Track, brick: Brick)? { model.selection() }

    var body: some View {
        if let sel, let bind = model.binding(forBrick: brickID) {
            let brick = sel.brick
            let defs = paramDefs(brick)
            let maxH = UIScreen.main.bounds.height * 0.45
            let content = VStack(alignment: .leading, spacing: 11) {
                header(brick)
                scopeRow(brick)
                if brick.isChain { chainRow(brick) }
                paramSliders(brick, bind: bind)
                actions(brick)
            }
                .padding(14)
            Group {
                if defs.count > 4 {
                    ScrollView { content }
                        .frame(maxHeight: maxH)
                        .scrollIndicators(.hidden)
                } else {
                    content
                }
            }
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

    /// Sliders are part of the scrolling inspector panel; the panel caps at ~45% of
    /// the screen height so it overlays the timeline instead of swallowing the canvas.
    private func paramSliders(_ brick: Brick, bind: Binding<Brick>) -> some View {
        slidersColumn(brick, bind: bind, defs: paramDefs(brick))
    }

    private func slidersColumn(_ brick: Brick, bind: Binding<Brick>,
                               defs: [EffectDef.Param]) -> some View {
        VStack(spacing: 9) {
            ForEach(defs, id: \.key) { p in
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

// MARK: - Shape clip inspector (ClipType::Shape)

/// Selected-shape-clip inspector — mirrors the brick InspectorView's chrome
/// (header + scrolling sliders, capped height, glass panel). Every control
/// routes through engine levers: set_shape_style for style fields,
/// set_clip_keyframes for the two scalar keyframable props, set_shape_keyframes
/// for morph keys.
struct ShapeInspectorView: View {
    @ObservedObject var model: EditorModel
    let clip: Clip
    @State private var showPathSheet = false
    @State private var style: ShapeStyleProj
    @State private var strokeLength: Double
    @State private var strokeWidthMul: Double

    init(model: EditorModel, clip: Clip) {
        self.model = model
        self.clip = clip
        let s = clip.shapeStyle ?? ShapeStyleProj()
        _style = State(initialValue: s)
        _strokeLength = State(initialValue: clip.shapeStrokeLength)
        _strokeWidthMul = State(initialValue: clip.shapeStrokeWidthMul)
    }

    private var maxH: CGFloat { UIScreen.main.bounds.height * 0.55 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                pathRow
                fillSection
                strokeSection
                gradientSection
                glowSection
                revealSection
                widthMulSection
                morphKeysSection
                actions
            }
            .padding(14)
        }
        .frame(maxHeight: maxH)
        .scrollIndicators(.hidden)
        .glass(18)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .sheet(isPresented: $showPathSheet) {
            ShapeEditorSheet(model: model, clipID: clip.id)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "diamond.fill").font(.system(size: 16))
                .foregroundStyle(Theme.bodyViolet)
                .frame(width: 30, height: 30)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.bodyViolet.opacity(0.6)))
            VStack(alignment: .leading, spacing: 1) {
                Text((clip.shapePreset.isEmpty ? "SHAPE" : clip.shapePreset.uppercased()))
                    .font(.disp(13)).foregroundStyle(.white).lineLimit(1)
                Text("\(fullTC(clip.start)) → \(fullTC(clip.end)) · \(String(format: "%.1f", clip.duration))s")
                    .font(.num(11.5)).foregroundStyle(Theme.txtMuted)
            }
            Spacer()
            ItemActionsMenu(model: model, id: clip.id)
            Button { model.selectedID = nil } label: {
                Image(systemName: "xmark").font(.system(size: 14)).foregroundStyle(Theme.txtMuted)
                    .frame(width: 30, height: 30)
            }
        }
    }

    private var pathRow: some View {
        Button { showPathSheet = true } label: {
            Label("Edit Path / Freehand", systemImage: "scribble.variable")
                .font(.label(11)).tracking(0.5).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.bodyViolet.opacity(0.4)))
        }
    }

    // MARK: Fill

    private var fillSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            rowLabel("FILL")
            HStack {
                Toggle("", isOn: Binding(get: { style.fillOn },
                                         set: { style.fillOn = $0; send("fill_on", $0) }))
                    .labelsHidden()
                ColorPicker("", selection: rgbaBinding("fill_col", current: style.fillCol),
                            supportsOpacity: true).labelsHidden()
                Spacer()
            }
        }
    }

    // MARK: Stroke

    private var strokeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            rowLabel("STROKE")
            HStack {
                Toggle("", isOn: Binding(get: { style.strokeOn },
                                         set: { style.strokeOn = $0; send("stroke_on", $0) }))
                    .labelsHidden()
                ColorPicker("", selection: rgbaBinding("stroke_col", current: style.strokeCol),
                            supportsOpacity: true).labelsHidden()
                Spacer()
            }
            sliderRow("Width", value: Binding(get: { style.strokeWidth },
                                              set: { style.strokeWidth = $0; send("stroke_width", $0) }),
                       range: 0.001...0.05, fmt: "%.3f")
        }
    }

    // MARK: Gradient

    private var gradientSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            rowLabel("GRADIENT")
            Picker("Mode", selection: Binding(get: { style.gradMode },
                                              set: { style.gradMode = $0; send("grad_mode", $0) })) {
                Text("None").tag(0); Text("Linear").tag(1)
                Text("Radial").tag(2); Text("Hue Cycle").tag(3)
            }.pickerStyle(.segmented)
            if style.gradMode != 0 && style.gradMode != 3 {
                HStack {
                    Text("2nd").font(.label(9)).foregroundStyle(Theme.txtMuted)
                    ColorPicker("", selection: rgbaBinding("grad_col2", current: style.gradCol2),
                                supportsOpacity: true).labelsHidden()
                    Spacer()
                }
                sliderRow("Angle", value: Binding(get: { style.gradAngle },
                                                  set: { style.gradAngle = $0; send("grad_angle", $0) }),
                           range: 0...360, fmt: "%.0f°")
            }
        }
    }

    // MARK: Glow

    private var glowSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            rowLabel("GLOW")
            HStack {
                Toggle("", isOn: Binding(get: { style.glowOn },
                                         set: { style.glowOn = $0; send("glow_on", $0) }))
                    .labelsHidden()
                ColorPicker("", selection: rgbaBinding("glow_col", current: style.glowCol),
                            supportsOpacity: true).labelsHidden()
                Spacer()
            }
            sliderRow("Radius", value: Binding(get: { style.glowRadius },
                                               set: { style.glowRadius = $0; send("glow_radius", $0) }),
                       range: 0...0.1, fmt: "%.3f")
            sliderRow("Intensity", value: Binding(get: { style.glowIntensity },
                                                  set: { style.glowIntensity = $0; send("glow_intensity", $0) }),
                       range: 0...3, fmt: "%.2f")
        }
    }

    // MARK: Draw-on reveal + width multiplier (keyframable scalars)

    private var revealSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                rowLabel("DRAW-ON REVEAL")
                Spacer()
                keyButton("shape_stroke_length", value: strokeLength)
            }
            sliderRow("Length", value: Binding(get: { strokeLength },
                                               set: { strokeLength = $0; sendScalar("shape_stroke_length", $0) }),
                       range: 0...1, fmt: "%.2f")
            keyList("shape_stroke_length")
        }
    }

    private var widthMulSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                rowLabel("STROKE WIDTH ×")
                Spacer()
                keyButton("shape_stroke_width_mul", value: strokeWidthMul)
            }
            sliderRow("Multiplier", value: Binding(get: { strokeWidthMul },
                                                   set: { strokeWidthMul = $0; sendScalar("shape_stroke_width_mul", $0) }),
                       range: 0.1...5, fmt: "%.2f")
            keyList("shape_stroke_width_mul")
        }
    }

    // MARK: Morph keys (path keyframes)

    private var morphKeysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            rowLabel("MORPH KEYS")
            if clip.shapeKeys.isEmpty {
                Text("No path keys — add one to morph between shapes.")
                    .font(.label(9)).foregroundStyle(Theme.txtMuted)
            } else {
                // Swipe-to-delete isn't available outside a List; provide a
                // delete button per key as the accessible equivalent.
                ForEach(Array(clip.shapeKeys.enumerated()), id: \.element.id) { i, k in
                    HStack {
                        Image(systemName: "diamond.fill").font(.system(size: 8))
                            .foregroundStyle(Theme.bodyViolet)
                        Text(String(format: "key %d · %.2fs", i + 1, k.time))
                            .font(.num(11)).foregroundStyle(Theme.txtBody)
                        Spacer()
                        Button(role: .destructive) { model.removeShapeMorphKey(clip.id, index: i) } label: {
                            Image(systemName: "minus.circle.fill").font(.system(size: 14))
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
                }
            }
            Button { model.addShapeMorphKey(clip.id) } label: {
                Label("Add key at playhead", systemImage: "plus.circle")
                    .font(.label(10)).tracking(0.4).foregroundStyle(Theme.accent)
            }
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 7) {
            inspectorButton("Split", tint: Theme.txt) { model.splitAtPlayhead() }
                .disabled(!(model.playhead > clip.start + 0.1 && model.playhead < clip.end - 0.1))
            inspectorButton("Delete", tint: Color(red: 1, green: 0.55, blue: 0.55)) {
                model.deleteClipAnywhere(clip.id)
            }
        }
    }

    // MARK: Helpers

    private func rowLabel(_ s: String) -> some View {
        Text(s).font(.label(9)).tracking(0.8).foregroundStyle(Theme.txtMuted)
    }

    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, fmt: String) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(label.uppercased()).font(.label(8.5)).tracking(0.8).foregroundStyle(Theme.txtMuted)
                Spacer()
                Text(String(format: fmt, value.wrappedValue)).font(.num(10)).foregroundStyle(Theme.accent)
            }
            Slider(value: value, in: range).tint(Theme.bodyViolet)
        }
    }

    private func inspectorButton(_ label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.label(10)).tracking(0.6).foregroundStyle(tint)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.35)))
        }
    }

    /// Keyframe button: adds a scalar key at the playhead with the current value.
    private func keyButton(_ prop: String, value: Double) -> some View {
        Button { model.addShapeScalarKey(clip.id, prop: prop, value: value) } label: {
            Image(systemName: "diamond.fill").font(.system(size: 12)).foregroundStyle(Theme.accent)
        }
    }

    /// List of existing scalar key times for a prop, with delete.
    @ViewBuilder
    private func keyList(_ prop: String) -> some View {
        if let keys = clip.shapeScalarKeys[prop], !keys.isEmpty {
            VStack(spacing: 4) {
                ForEach(Array(keys.enumerated()), id: \.offset) { i, k in
                    HStack {
                        Image(systemName: "diamond.fill").font(.system(size: 7)).foregroundStyle(Theme.accent)
                        Text(String(format: "%.2fs = %.2f", k.time, k.value))
                            .font(.num(10)).foregroundStyle(Theme.txtBody)
                        Spacer()
                        Button(role: .destructive) { model.removeShapeScalarKey(clip.id, prop: prop, index: i) } label: {
                            Image(systemName: "minus.circle.fill").font(.system(size: 13))
                        }
                    }
                }
            }
        }
    }

    // MARK: Lever sends

    private func send(_ key: String, _ value: Any) {
        model.setShapeStyle(clip.id, key: key, value: value)
    }
    private func sendScalar(_ prop: String, _ value: Double) {
        // The engine exposes shape_stroke_length / shape_stroke_width_mul only
        // through set_clip_keyframes (no set_clip_prop for them), so the slider
        // writes the value via the keyframe track — a single t=0 key acts as
        // the constant base; with existing keys, the nearest one is updated.
        model.setShapeScalar(clip.id, prop: prop, value: value)
    }

    /// ColorPicker binding ↔ engine [r,g,b,a] (0–1 doubles).
    private func rgbaBinding(_ key: String, current: [Double]) -> Binding<Color> {
        Binding(
            get: { ShapeRGBA.color(current) },
            set: { c in
                let a = ShapeRGBA.rgba(c)
                style.setArray(key, a)
                model.setShapeStyle(clip.id, key: key, value: a)
            }
        )
    }
}

private enum ShapeRGBA {
    static func color(_ a: [Double]) -> Color {
        Color(.sRGB, red: a[safe: 0] ?? 1, green: a[safe: 1] ?? 1,
              blue: a[safe: 2] ?? 1, opacity: a[safe: 3] ?? 1)
    }
    static func rgba(_ c: Color) -> [Double] {
        let u = UIColor(c)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, al: CGFloat = 0
        u.getRed(&r, green: &g, blue: &b, alpha: &al)
        return [Double(r), Double(g), Double(b), Double(al)]
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

private extension ShapeStyleProj {
    mutating func setArray(_ key: String, _ a: [Double]) {
        switch key {
        case "fill_col":   fillCol = a
        case "stroke_col": strokeCol = a
        case "grad_col2":  gradCol2 = a
        case "glow_col":   glowCol = a
        default: break
        }
    }
}
