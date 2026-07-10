#!/usr/bin/env python3
"""Patch PopMakerOrbs.swift cluster composition: bring foreground orbs closer
so they overlap, creating the iOS 26 layered glass feel."""
import pathlib, sys

P = "Sources/PopMakerOrbs.swift"
src = pathlib.Path(P).read_text()

old = (
    '        case .cluster:\n'
    '            return [\n'
    '                Orb(nx: 0.50, ny: 0.42, size: 0.38, blur: 0.003, opacity: 0.96, color: c(0)),\n'
    '                Orb(nx: 0.22, ny: 0.62, size: 0.26, blur: 0.010, opacity: 0.88, color: c(1 % cols.count)),\n'
    '                Orb(nx: 0.78, ny: 0.58, size: 0.22, blur: 0.014, opacity: 0.82, color: c(2 % cols.count)),\n'
    '                Orb(nx: 0.38, ny: 0.82, size: 0.16, blur: 0.030, opacity: 0.65, color: c(0)),\n'
    '                Orb(nx: 0.66, ny: 0.22, size: 0.14, blur: 0.036, opacity: 0.58, color: c(1 % cols.count)),\n'
    '            ]\n'
)
new = (
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
if "layered glass" in src:
    print("  already patched")
else:
    if old not in src:
        sys.exit("ANCHOR NOT FOUND")
    src = src.replace(old, new, 1)
    pathlib.Path(P).write_text(src)
    print("  patched: cluster orbs now overlap")

print("done")
