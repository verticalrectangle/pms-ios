#!/usr/bin/env python3
"""Patch IconView.swift to pass glassForeground/glassTinted to PopMakerOrbs,
reading from ENCLAVE_GLASS_ORBS and ENCLAVE_GLASS_TINTED env vars."""
import pathlib, sys

IV = "Sources/IconView.swift"
src = pathlib.Path(IV).read_text()

# 1. Add glass orb properties after orbColors property
anchor = (
    '    private let orbColors: [Color] = {\n'
    '        let raw = ProcessInfo.processInfo.environment["ENCLAVE_ORB_COLORS"] ?? "B5A8FF,6B99FF,FFAE80"\n'
    '        return raw.split(separator: ",").compactMap { UInt($0, radix: 16).map { Color(hex: $0) } }\n'
    '    }()\n'
)
new_props = anchor + (
    '    private let glassForeground: Bool = {\n'
    '        ProcessInfo.processInfo.environment["ENCLAVE_GLASS_ORBS"] == "1"\n'
    '    }()\n'
    '    private let glassTinted: Bool = {\n'
    '        ProcessInfo.processInfo.environment["ENCLAVE_GLASS_TINTED"] == "1"\n'
    '    }()\n'
)
if "glassForeground" in src:
    print("  glass orb properties already present")
else:
    if anchor not in src:
        sys.exit("ANCHOR (orbColors property) NOT FOUND")
    src = src.replace(anchor, new_props, 1)
    print("  added glass orb properties")

# 2. Update PopMakerOrbs call to pass new params
old_call = 'PopMakerOrbs(composition: orbComposition, ground: orbGround, orbColors: orbColors)'
new_call = 'PopMakerOrbs(composition: orbComposition, ground: orbGround, orbColors: orbColors, glassForeground: glassForeground, glassTinted: glassTinted)'
if "glassForeground: glassForeground" in src:
    print("  PopMakerOrbs call already updated")
else:
    if old_call not in src:
        sys.exit("ANCHOR (PopMakerOrbs call) NOT FOUND")
    src = src.replace(old_call, new_call, 1)
    print("  updated PopMakerOrbs call")

pathlib.Path(IV).write_text(src)
print("done")
