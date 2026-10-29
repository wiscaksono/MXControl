#!/usr/bin/env bash
set -euo pipefail

BIN="${1:?usage: bundle.sh <binary> <app>}"
APP="${2:?usage: bundle.sh <binary> <app>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXECUTABLE="MXControl"

cd "$ROOT"

if [[ ! -f "$BIN" ]]; then
  echo "binary not found: $BIN" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$EXECUTABLE"
cp scripts/Info.plist "$APP/Contents/Info.plist"
cp Sources/Resources/logi-logo.png "$APP/Contents/Resources/logi-logo.png"
cp Sources/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc keeps local builds simple, but macOS ties HID access and TCC grants
# to a signing identity. Pass SIGNING_IDENTITY to use a real certificate.
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

# Nested bundles are not present yet, so one signature is enough. When helpers
# or extensions show up, sign them first, then the outer app.
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --sign - \
    --entitlements scripts/Entitlements.plist \
    "$APP"
else
  codesign --force --sign "$SIGNING_IDENTITY" \
    --options runtime \
    --entitlements scripts/Entitlements.plist \
    "$APP"
fi
codesign --verify --strict "$APP"

echo "bundled $APP"
