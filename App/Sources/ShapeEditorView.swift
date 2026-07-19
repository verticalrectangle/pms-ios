//  ShapeEditorView.swift
//  Shape clip creation + path editing. Two surfaces live here:
//   - ShapeEditorSheet: a GlassSheet with a Preset picker (12 presets → add_shape)
//     and a Freehand Draw tab (PKCanvasView → set_shape_path). In edit mode
//     (clipID != nil) it also shows draggable path handles.
//   - The sheet is presented from the dock's Shape tool (create) or the shape
//     inspector's "Edit Path" button (edit).
// All mutations cross the engine levers (add_shape / set_shape_path); the
// engine owns tessellation + rendering — the UI only drives the path.

import SwiftUI
import PencilKit

// MARK: - Sheet

struct ShapeEditorSheet: View {
    @ObservedObject var model: EditorModel
    var clipID: String?            // nil → create mode; non-nil → edit path

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .preset
    @State private var drawing = PKDrawing()
    @State private var canvasSize: CGSize = .zero
    @State private var pathPoints: [ShapePoint] = []
    @State private var pathClosed = false
    @State private var didLoadPath = false

    enum Mode { case preset, draw }

    /// The 12 engine presets (shape_preset_name) + an SF Symbol for each.
    private let presets: [(name: String, symbol: String)] = [
        ("circle", "circle"),        ("square", "square"),
        ("triangle", "triangle"),    ("star", "star.fill"),
        ("heart", "heart.fill"),     ("polygon", "pentagon"),
        ("hexagon", "hexagon"),      ("burst", "asterisk"),
        ("arrow", "arrow.up.right"), ("lightning", "bolt.fill"),
        ("diamond", "diamond"),      ("cross", "plus"),
    ]

    var body: some View {
        GlassSheet(title: clipID == nil ? "New Shape" : "Edit Path",
                   eyebrow: "SHAPE · VECTOR CLIP", full: true) {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Mode", selection: $mode) {
                    Text("Presets").tag(Mode.preset)
                    Text("Draw").tag(Mode.draw)
                }
                .pickerStyle(.segmented)

                if mode == .preset {
                    presetGrid
                } else {
                    drawSection
                }

                if clipID != nil {
                    pathHandleSection
                        .onAppear { loadPath() }
                }
            }
        }
    }

    // MARK: Preset picker

    private var presetGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tap a preset to drop it at the playhead.")
                .font(.label(9)).foregroundStyle(Theme.txtMuted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                      spacing: 10) {
                ForEach(presets, id: \.name) { p in
                    Button {
                        createPreset(p.name)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: p.symbol)
                                .font(.system(size: 22)).foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                            Text(p.name.capitalized)
                                .font(.label(8.5)).tracking(0.3).foregroundStyle(Theme.txtBody)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .glass(Theme.rTile)
                    }
                }
            }
        }
    }

    private func createPreset(_ name: String) {
        model.addShapeClip(preset: name)
        dismiss()
    }

    // MARK: Freehand draw

    private var drawSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Draw with Apple Pencil or a finger. The stroke becomes the shape path (local 0–1 space).")
                .font(.label(9)).foregroundStyle(Theme.txtMuted)
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04))
                RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, lineWidth: 1)
                PencilCanvas(drawing: $drawing, size: $canvasSize)
                // Live preview of the captured stroke in local space.
                if !drawing.strokes.isEmpty {
                    strokePreview
                }
            }
            .aspectRatio(1, contentMode: .fit)
            HStack(spacing: 10) {
                Button { drawing = PKDrawing() } label: {
                    Label("Clear", systemImage: "trash").font(.label(11))
                }.tint(Theme.txtBody)
                    .disabled(drawing.strokes.isEmpty)
                Spacer()
                Button { commitDraw() } label: {
                    Label(clipID == nil ? "Create Shape" : "Apply Path",
                          systemImage: "checkmark.circle.fill").font(.label(11))
                }.tint(Theme.accent)
                    .disabled(drawing.strokes.isEmpty)
            }
        }
    }

    /// Render the latest stroke scaled into the square canvas (a visual sanity
    /// check that the captured points match what the user drew).
    private var strokePreview: some View {
        Canvas { ctx, size in
            guard let stroke = drawing.strokes.last else { return }
            let s = canvasSize.width > 0 ? canvasSize.width : size.width
            let h = canvasSize.height > 0 ? canvasSize.height : size.height
            let pts = ShapeDraw.strokePoints(stroke)
            var p = Path()
            for (i, loc) in pts.enumerated() {
                let x = loc.x / s * size.width
                let y = loc.y / h * size.height
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(p, with: .color(.white.opacity(0.9)), lineWidth: 2)
        }
        .allowsHitTesting(false)
    }

    /// Convert the latest PencilKit stroke to local [0,1]² points and send it
    /// through the engine. In create mode, a placeholder shape clip is created
    /// first (add_shape), then its base path is replaced (set_shape_path).
    private func commitDraw() {
        guard let stroke = drawing.strokes.last, stroke.path.count > 0,
              canvasSize.width > 0, canvasSize.height > 0 else { return }
        // Downsample: PencilKit strokes are dense (B-spline control points);
        // keep every Nth point + the last so the engine gets a manageable polyline.
        let pts = ShapeDraw.strokePoints(stroke)
        let step = max(1, pts.count / 64)
        var local: [[String: Any]] = []
        for i in stride(from: 0, to: pts.count, by: step) {
            local.append(pointDict(pts[i]))
        }
        if let last = pts.last {
            local.append(pointDict(last))
        }
        let closed = false   // freehand strokes are open by default

        if let id = clipID {
            model.beginCanvasGesture()
            model.setShapePath(id, points: local, closed: closed)
            model.endCanvasGesture()
        } else {
            // Create a placeholder shape, then override its path with the draw.
            if let id = model.addShapeClip(preset: "square") {
                model.setShapePath(id, points: local, closed: closed)
            }
        }
        drawing = PKDrawing()
        dismiss()
    }

    private func pointDict(_ loc: CGPoint) -> [String: Any] {
        ["x": max(0, min(1, Double(loc.x / canvasSize.width))),
         "y": max(0, min(1, Double(loc.y / canvasSize.height))),
         "w": 0.008] as [String: Any]
    }

    // MARK: Path handle editor (edit mode)

    private var pathHandleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PATH HANDLES").font(.label(9)).tracking(0.8).foregroundStyle(Theme.txtMuted)
                Spacer()
                Toggle("Closed", isOn: $pathClosed)
                    .toggleStyle(.switch).controlSize(.mini)
                    .onChange(of: pathClosed) { _, v in commitHandles() }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04))
                RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, lineWidth: 1)
                GeometryReader { geo in
                    let s = min(geo.size.width, geo.size.height)
                    Canvas { ctx, _ in
                        var p = Path()
                        for (i, pt) in pathPoints.enumerated() {
                            let c = CGPoint(x: pt.x * s, y: pt.y * s)
                            if i == 0 { p.move(to: c) } else { p.addLine(to: c) }
                        }
                        if pathClosed, !pathPoints.isEmpty { p.closeSubpath() }
                        ctx.stroke(p, with: .color(Theme.accent.opacity(0.9)), lineWidth: 1.5)
                    }
                    ForEach(Array(pathPoints.enumerated()), id: \.offset) { i, pt in
                        Circle().fill(.white).frame(width: 14, height: 14)
                            .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 2))
                            .position(x: pt.x * s, y: pt.y * s)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { v in
                                        let nx = max(0, min(1, v.location.x / s))
                                        let ny = max(0, min(1, v.location.y / s))
                                        pathPoints[i].x = nx
                                        pathPoints[i].y = ny
                                    }
                                    .onEnded { _ in commitHandles() }
                            )
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)

            HStack(spacing: 10) {
                Button {
                    model.addShapeMorphKey(clipID ?? "")
                } label: {
                    Label("Key Path", systemImage: "diamond.fill").font(.label(10))
                }.tint(Theme.accent)
                Spacer()
                Button { loadPath() } label: {
                    Label("Reload", systemImage: "arrow.clockwise").font(.label(10))
                }.tint(Theme.txtBody)
            }
        }
    }

    private func loadPath() {
        guard let id = clipID else { return }
        if let p = model.engineShapePath(id) {
            pathPoints = p.points
            pathClosed = p.closed
            didLoadPath = true
        } else if let c = model.tracks.flatMap(\.clips).first(where: { $0.id == id }),
                  let p = c.shapePath {
            pathPoints = p.points
            pathClosed = p.closed
        }
    }

    /// Batch the handle drag as one engine history entry (begin_batch →
    /// set_shape_path → end_batch), matching the canvas gesture pattern.
    private func commitHandles() {
        guard let id = clipID, !pathPoints.isEmpty else { return }
        let pts: [[String: Any]] = pathPoints.map {
            ["x": $0.x, "y": $0.y, "w": $0.width] as [String: Any]
        }
        model.beginCanvasGesture()
        model.setShapePath(id, points: pts, closed: pathClosed)
        model.endCanvasGesture()
    }
}

// MARK: - PencilKit canvas bridge

/// A PKCanvasView that accepts both Pencil and finger input and reports its
/// size (so the sheet can map stroke points to local [0,1]² space).
struct PencilCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var size: CGSize

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput        // finger + Pencil
        canvas.tool = PKInkingTool(.pen, color: .white, width: 4)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.delegate = context.coordinator
        canvas.drawing = drawing
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing { uiView.drawing = drawing }
        let s = uiView.bounds.size
        if s.width > 0 && s != size { DispatchQueue.main.async { size = s } }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let parent: PencilCanvas
        init(_ parent: PencilCanvas) { self.parent = parent }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
            let s = canvasView.bounds.size
            if s.width > 0 && s != parent.size {
                let p = parent
                DispatchQueue.main.async { p.size = s }
            }
        }
    }
}

/// Pull the on-curve control-point locations out of a PencilKit stroke.
/// PKStroke exposes its samples via `path` (a PKStrokePath of B-spline control
/// points), not a `points` array — this walks `path.count` and reads each
/// `point(at:)` location in canvas-view coordinate space.
enum ShapeDraw {
    static func strokePoints(_ stroke: PKStroke) -> [CGPoint] {
        // PKStrokePath is a RandomAccessCollection of PKStrokePoint; iterate
        // it directly (its Index type isn't a plain Int).
        stroke.path.map(\.location)
    }
}
