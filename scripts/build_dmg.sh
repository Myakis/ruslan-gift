#!/bin/bash
# Packages a built .app into a plain drag-to-Applications DMG.
# Usage: build_dmg.sh <path/to/App.app> <path/to/output.dmg> [volume name]
#
# No AppleScript/Finder window-layout step here — that requires an
# interactive Finder session and is flaky on a headless CI runner. This
# produces a functional (if plain) installer: open the DMG, drag the app
# into the Applications shortcut next to it.
set -euo pipefail

APP_PATH="$1"
DMG_OUT="$2"
VOLUME_NAME="${3:-Wplan}"

if [ ! -d "$APP_PATH" ]; then
  echo "error: app bundle not found at $APP_PATH" >&2
  exit 1
fi

STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_OUT"
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_OUT"

echo "Built $DMG_OUT"
