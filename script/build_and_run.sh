#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="RowPlayStudio"
BUNDLE_ID="com.shenghaoc.RowPlayStudio"
MIN_SYSTEM_VERSION="26.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build --package-path "$ROOT_DIR"
BUILD_BINARY="$(swift build --package-path "$ROOT_DIR" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

# Generate Info.plist with stable technical identity.
# CFBundleName = RowPlayStudio (matches executable, used for app discovery)
# CFBundleDisplayName = RowPlay Studio (human-facing name)
cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>RowPlay Studio</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc sign the staged bundle for consistent identity and accessibility discovery
codesign --force --deep --sign - "$APP_BUNDLE" || true

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

open_app_automation() {
  /usr/bin/open -n --env ROWPLAY_AUTOMATION=1 "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --automation|automation)
    echo "Launching in automation mode (demo data, reduced motion)..."
    open_app_automation
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    echo "Automation launch verified."
    ;;
  --sign-verify|sign-verify)
    echo "Verifying bundle signature..."
    plutil -lint "$INFO_PLIST"
    codesign --verify --deep --strict "$APP_BUNDLE"
    codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1 | grep -E "^(Identifier|TeamIdentifier|Signature)" || true
    echo "Bundle verification complete."
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--automation|--sign-verify]" >&2
    exit 2
    ;;
esac
