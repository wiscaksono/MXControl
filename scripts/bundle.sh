#!/usr/bin/env bash
set -euo pipefail

BIN="${1:?usage: bundle.sh <binary> <app>}"
APP="${2:?usage: bundle.sh <binary> <app>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXECUTABLE="MenuBarApp"

cd "$ROOT"

if [[ ! -f "$BIN" ]]; then
  echo "binary not found: $BIN" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$EXECUTABLE"
cp scripts/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# No nested bundles yet, so one ad-hoc signature is enough. When helpers or
# extensions show up, sign them first, then the outer app.
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"

echo "bundled $APP"
