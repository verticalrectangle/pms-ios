#!/usr/bin/env python3
"""GLSL → SPIR-V → MSL transpiler for the PMS effect shaders.

The desktop engine authors effects in GLSL 330 with loose uniforms
(set by name via glGetUniformLocation). Metal has no loose uniforms, so
this tool:

  1. lifts non-opaque uniforms into a std140 uniform block (binding 0),
     samplers get explicit bindings (1..N);
  2. compiles with glslangValidator -V (Vulkan semantics);
  3. cross-compiles to MSL with spirv-cross;
  4. emits a params manifest (JSON) with each shader's std140 field
     offsets — the Metal renderer fills one buffer per draw using this
     ABI, mirroring what the GL renderer does with glUniform*.

GLSL stays the single source of truth: registry shaders are transpiled
verbatim; nothing is hand-ported.

Usage:
  transpile_shaders.py --glslang glslangValidator --spirv-cross spirv-cross \
      --out-dir Shaders/msl --manifest Shaders/msl/params_manifest.json \
      <shader.glsl> [...]
"""
import argparse, json, os, re, subprocess, sys, tempfile

SCALARS = {  # std140: (size, align)
    "float": (4, 4), "int": (4, 4), "uint": (4, 4), "bool": (4, 4),
    "vec2": (8, 8), "ivec2": (8, 8),
    "vec3": (12, 16), "ivec3": (12, 16),
    "vec4": (16, 16), "ivec4": (16, 16),
}

UNIFORM_RE = re.compile(
    r"^\s*uniform\s+(?P<type>\w+)\s+(?P<names>\w+\s*(?:\[\s*\d+\s*\])?"
    r"(?:\s*,\s*\w+\s*(?:\[\s*\d+\s*\])?)*)\s*;", re.M)
NAME_RE = re.compile(r"(\w+)\s*(?:\[\s*(\d+)\s*\])?")


def lift_uniforms(src):
    """Move non-opaque uniforms into a std140 block; return (new_src, params)."""
    params, samplers, spans = [], [], []
    for m in UNIFORM_RE.finditer(src):
        ty = m.group("type")
        decls = [NAME_RE.match(d.strip()).groups()
                 for d in m.group("names").split(",")]
        if ty.startswith("sampler"):
            for name, _ in decls:
                samplers.append((name, ty))
            continue
        if ty not in SCALARS:
            raise ValueError(f"unhandled uniform type {ty}")
        for name, count in decls:
            params.append({"name": name, "type": ty,
                           "count": int(count) if count else 0})
        spans.append(m.span())
    # remove lifted declarations (reverse order keeps spans valid)
    for a, b in reversed(spans):
        src = src[:a] + src[b:]
    if params:
        block = ["layout(std140, binding = 0) uniform Params {"]
        off = 0
        for p in params:
            size, align = SCALARS[p["type"]]
            if p["count"]:                       # arrays: stride 16 per std140
                align = 16
                stride = (size + 15) // 16 * 16
                total = stride * p["count"]
            else:
                stride, total = size, size
            off = (off + align - 1) // align * align
            p["offset"], p["stride"] = off, stride
            off += total
            arr = f"[{p['count']}]" if p["count"] else ""
            block.append(f"    {p['type']} {p['name']}{arr};")
        block.append("};")
        blob_size = (off + 15) // 16 * 16
        # insert after #version line
        lines = src.split("\n")
        vi = next(i for i, l in enumerate(lines) if l.startswith("#version"))
        lines[vi + 1:vi + 1] = block
        src = "\n".join(lines)
    else:
        blob_size = 0
    # samplers: explicit bindings after the block
    for i, (name, ty) in enumerate(samplers):
        src = re.sub(rf"^\s*uniform\s+{ty}\s+{name}\s*;",
                     f"layout(binding = {i + 1}) uniform {ty} {name};",
                     src, count=1, flags=re.M)
    return src, params, [n for n, _ in samplers], blob_size


def transpile(path, args):
    name = os.path.splitext(os.path.basename(path))[0]
    src = open(path).read()
    # Vulkan pass needs 450; the source is desktop 330. Purely a compile-
    # target bump — the shader text is otherwise verbatim.
    src = re.sub(r"#version .*", "#version 450", src, count=1)
    lifted, params, samplers, blob = lift_uniforms(src)
    with tempfile.TemporaryDirectory() as td:
        frag = os.path.join(td, name + ".frag")
        spv = os.path.join(td, name + ".spv")
        open(frag, "w").write(lifted)
        r = subprocess.run([args.glslang, "-V", "--auto-map-locations",
                            "-o", spv, frag], capture_output=True, text=True)
        if r.returncode:
            return None, f"glslang: {r.stdout.strip()[:400]}"
        out_msl = os.path.join(args.out_dir, name + ".metal")
        r = subprocess.run([args.spirv_cross, spv, "--msl",
                            "--msl-version", "20300",
                            "--rename-entry-point", "main",
                            f"fx_{name}", "frag",
                            "--output", out_msl],
                           capture_output=True, text=True)
        if r.returncode:
            return None, f"spirv-cross: {r.stderr.strip()[:400]}"
    return {"shader": name, "params": params, "samplers": samplers,
            "params_size": blob, "entry": f"fx_{name}"}, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--glslang", default="glslangValidator")
    ap.add_argument("--spirv-cross", default="spirv-cross")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("shaders", nargs="+")
    args = ap.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)
    manifest, failures = [], []
    for path in args.shaders:
        entry, err = transpile(path, args)
        if err:
            failures.append((os.path.basename(path), err))
            print(f"FAIL {os.path.basename(path)}: {err}", file=sys.stderr)
        else:
            manifest.append(entry)
            print(f"ok   {entry['shader']} ({len(entry['params'])} params, "
                  f"{entry['params_size']}B block)")
    json.dump(manifest, open(args.manifest, "w"), indent=1)
    print(f"\n{len(manifest)} transpiled, {len(failures)} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
