//  PopMakerGlyph.swift
//  The PopMaker Studio figure: a play triangle — the universal video symbol.
//  Drawn in a normalized 0…1 box so it scales like EnclaveSlit. Works as both
//  .fill (liquidMark glass sculpt) and .stroke (flatGlass etched seam).

import SwiftUI

struct PopMakerGlyph: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * w, y: r.minY + y * h) }
        var path = Path()
        // Right-pointing play triangle, optically centered (shifted left so the
        // visual centroid sits at 0.5,0.5 — the geometric centroid is at 0.47,0.5).
        path.move(to: p(0.36, 0.28))
        path.addLine(to: p(0.70, 0.50))
        path.addLine(to: p(0.36, 0.72))
        path.closeSubpath()
        return path
    }
}
