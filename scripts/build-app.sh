#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ArgoCDMenubar"
BUILD_DIR="$ROOT/.build/release"
APP_BUNDLE="$ROOT/$APP_NAME.app"

echo "Building $APP_NAME..."
cd "$ROOT"
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT/ArgoCDMenubar/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "Built: $APP_BUNDLE"
echo "Run: open \"$APP_BUNDLE\""
