#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/build/snapshots"
OUT="$ROOT/docs/images"

if ! command -v magick >/dev/null 2>&1; then
  echo "imagemagick required for screenshots: brew install imagemagick" >&2
  exit 1
fi

if [[ ! -f "$SRC/root-clean-light.png" ]]; then
  echo "snapshots missing; run make snapshot first" >&2
  exit 1
fi

mkdir -p "$OUT"

# Hero: the full popover with two connected devices, light and dark.
magick "$SRC/root-clean-light.png" -strip "$OUT/preview-light.png"
magick "$SRC/root-clean-dark.png" -strip "$OUT/preview-dark.png"

# Device screens: keep the identity bar and the main controls.
magick "$SRC/device-mouse-light.png" \
  -crop 640x860+0+0 +repage -resize 320x -strip "$OUT/mouse.png"
magick "$SRC/device-keyboard-light.png" \
  -crop 640x860+0+0 +repage -resize 320x -strip "$OUT/keyboard.png"

# Onboarding wizard.
magick "$SRC/onboarding-light.png" -resize 300x -strip "$OUT/onboarding.png"

echo "screenshots written to $OUT"
