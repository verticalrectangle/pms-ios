#!/usr/bin/env python3
"""Patch PopMakerOrbs.swift cluster: more overlapping foreground orbs in
various sizes + one separate orb off to the side. 5 tight overlapping glass
orbs + 1 separate + 2 blurred bokeh behind = 8 total."""
import pathlib, sys

P = "Sources/PopMakerOrbs.swift"
src = pathlib.Path(P).read_text()

old = (
    '        case .cluster:\n'
    '            // Foreground glass orbs overlap for the iOS 26 layered glass feel.\n'
    '            // 3 sharp orbs clustered tight + 2 blurred bokeh behind.\n'
    '            return [\n'
    '                Orb(nx: 0.46, ny: 0.52, size: 0.36, blur: 0.003, opacity: 0.96, color: c(0)),\n'
    '                Orb(nx: 0.30, ny: 0.62, size: 0.28, blur: 0.008, opacity: 0.92, color: c(1 % cols.count)),\n'
    '                Orb(nx: 0.62, ny: 0.46, size: 0.24, blur: 0.012, opacity: 0.88, color: c(2 % cols.count)),\n'
    '                Orb(nx: 0.42, ny: 0.80, size: 0.16, blur: 0.030, opacity: 0.65, color: c(0)),\n'
    '                Orb(nx: 0.70, ny: 0.24, size: 0.14, blur: 0.036, opacity: 0.58, color: c(1 % cols.count)),\n'
    '            ]\n'
)
new = (
    '        case .cluster:\n'
    '            // 5 overlapping glass orbs in various sizes (packed tight for the\n'
    '            // iOS 26 layered glass feel) + 1 separate orb off to the side +\n'
    '            // 2 blurred bokeh behind = 8 total.\n'
    '            return [\n'
    '                // — blurred background bokeh —\n'
    '                Orb(nx: 0.72, ny: 0.82, size: 0.20, blur: 0.030, opacity: 0.60, color: c(2 % cols.count)),\n'
    '                Orb(nx: 0.22, ny: 0.18, size: 0.16, blur: 0.036, opacity: 0.55, color: c(1 % cols.count)),\n'
    '                // — overlapping foreground glass cluster (various sizes) —\n'
    '                Orb(nx: 0.44, ny: 0.50, size: 0.34, blur: 0.003, opacity: 0.96, color: c(0)),\n'
    '                Orb(nx: 0.28, ny: 0.58, size: 0.26, blur: 0.006, opacity: 0.93, color: c(1 % cols.count)),\n'
    '                Orb(nx: 0.58, ny: 0.44, size: 0.22, blur: 0.008, opacity: 0.90, color: c(2 % cols.count)),\n'
    '                Orb(nx: 0.38, ny: 0.66, size: 0.18, blur: 0.010, opacity: 0.88, color: c(0)),\n'
    '                Orb(nx: 0.54, ny: 0.62, size: 0.14, blur: 0.012, opacity: 0.85, color: c(1 % cols.count)),\n'
    '                // — one separate orb off to the side —\n'
    '                Orb(nx: 0.82, ny: 0.30, size: 0.12, blur: 0.010, opacity: 0.82, color: c(2 % cols.count)),\n'
    '            ]\n'
)
if "separate orb" in src:
    print("  already patched")
else:
    if old not in src:
        sys.exit("ANCHOR NOT FOUND")
    src = src.replace(old, new, 1)
    pathlib.Path(P).write_text(src)
    print("  patched: cluster now has 5 overlapping + 1 separate + 2 bokeh")

print("done")
