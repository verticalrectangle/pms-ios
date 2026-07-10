#!/bin/bash
# capture_pms.sh — render 20 PopMaker Studio icon tiles: glass foreground orbs
# on light ground. Foreground orbs are iOS 26 Liquid Glass; background orbs are
# opaque colored bokeh. No glass disc, no glyph — just orbs filling the tile.
set -euo pipefail
cd "$(dirname "$0")"

CAPTURE_UDID="${CAPTURE_UDID:-B943CA0E-37E4-4F27-BA2E-9D38C145A74F}"
BUNDLE=tools.enclave.IconRenderer

xcodegen generate
xcodebuild -scheme IconRenderer -destination "id=$CAPTURE_UDID" -derivedDataPath build -quiet build
xcrun simctl boot "$CAPTURE_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$CAPTURE_UDID" 2>/dev/null || true
xcrun simctl install "$CAPTURE_UDID" build/Build/Products/Debug-iphonesimulator/IconRenderer.app
mkdir -p out

# TSV: tag  comp  ground_hex  orb_colors  glass_tinted
TSV="$(python3 gen_pms_variants.py)"
n=0; total=20
while IFS=$'\t' read -r tag comp ground orb_colors glass_tinted; do
  [[ -z "$tag" ]] && continue
  n=$((n+1))
  out_path="out/pms-icon-$tag-1024.png"
  if [[ -f "$out_path" ]]; then echo "[$n/$total] skip $tag"; continue; fi
  xcrun simctl terminate "$CAPTURE_UDID" "$BUNDLE" 2>/dev/null || true
  SIMCTL_CHILD_ENCLAVE_ORBS="1" \
  SIMCTL_CHILD_ENCLAVE_ORB_COMP="$comp" \
  SIMCTL_CHILD_ENCLAVE_ORB_GROUND="$ground" \
  SIMCTL_CHILD_ENCLAVE_ORB_COLORS="$orb_colors" \
  SIMCTL_CHILD_ENCLAVE_GLASS_ORBS="1" \
  SIMCTL_CHILD_ENCLAVE_GLASS_TINTED="$glass_tinted" \
  SIMCTL_CHILD_ENCLAVE_GLYPH="liquidMark" \
  SIMCTL_CHILD_ENCLAVE_PM_GLYPH="0" \
  SIMCTL_CHILD_ENCLAVE_NO_GLYPH="1" \
  SIMCTL_CHILD_ENCLAVE_SPLIT="0" \
  SIMCTL_CHILD_ENCLAVE_INK="FFFFFF" \
  xcrun simctl launch "$CAPTURE_UDID" "$BUNDLE" >/dev/null
  sleep 5
  xcrun simctl io "$CAPTURE_UDID" screenshot "shot-$tag.png" >/dev/null
  xcrun simctl terminate "$CAPTURE_UDID" "$BUNDLE" 2>/dev/null || true
  W=$(sips -g pixelWidth  "shot-$tag.png" | awk '{print $2}')
  H=$(sips -g pixelHeight "shot-$tag.png" | awk '{print $2}')
  SIDE=$(( W < H ? W : H ))
  sips -c "$SIDE" "$SIDE" "shot-$tag.png" --out "crop-$tag.png" >/dev/null
  sips -z 1024 1024 "crop-$tag.png" --out "$out_path" >/dev/null
  rm -f "shot-$tag.png" "crop-$tag.png"
  echo "[$n/$total] $tag -> $out_path"
done <<< "$TSV"

echo "pms icons captured: $(ls out/pms-icon-*-1024.png 2>/dev/null | wc -l | tr -d ' ')"
