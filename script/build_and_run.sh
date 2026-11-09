#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="LogicScreen"
BUNDLE_ID="dev.logicscreen.app"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_MACOS="$APP_BUNDLE/Contents/MacOS"
cd "$ROOT_DIR"

case "$MODE" in
  run|--debug|--logs|--telemetry|--verify|--build-only|--fixture) ;;
  *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--build-only|--fixture]" >&2; exit 2 ;;
esac

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"
swift build --disable-sandbox --cache-path "$ROOT_DIR/.build/cache" --config-path "$ROOT_DIR/.build/config" --security-path "$ROOT_DIR/.build/security"
BUILD_DIR="$(swift build --show-bin-path --cache-path "$ROOT_DIR/.build/cache" --config-path "$ROOT_DIR/.build/config" --security-path "$ROOT_DIR/.build/security")"
mkdir -p "$APP_MACOS"
cp "$BUILD_DIR/$APP_NAME" "$APP_MACOS/$APP_NAME"
chmod +x "$APP_MACOS/$APP_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"

case "$MODE" in
  --build-only) echo "Built $APP_BUNDLE" ;;
  --debug) lldb -- "$APP_MACOS/$APP_NAME" ;;
  --fixture) /usr/bin/open -n "$APP_BUNDLE" --args --validation-fixture ;;
  --logs) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "LogicScreen"' ;;
  --telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "dev.logicscreen.app"' ;;
  --verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 1; pgrep -x "$APP_NAME" >/dev/null; echo "Launch verified" ;;
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
esac
