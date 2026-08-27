#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG="${SVG:-$ROOT/ArgoCDMenubar/Resources/Brand/argo-icon.svg}"
MENUBAR_SVG="${MENUBAR_SVG:-$ROOT/ArgoCDMenubar/Resources/Brand/argocd-menubar.svg}"
ICONSET="$ROOT/ArgoCDMenubar/Assets.xcassets/AppIcon.appiconset"
MENUSET="$ROOT/ArgoCDMenubar/Assets.xcassets/MenuBarIcon.imageset"

if [[ ! -f "$SVG" ]]; then
  echo "Missing source SVG: $SVG" >&2
  exit 1
fi

if [[ ! -f "$MENUBAR_SVG" ]]; then
  echo "Missing menu bar SVG: $MENUBAR_SVG" >&2
  exit 1
fi

if ! command -v magick >/dev/null 2>&1; then
  echo "ImageMagick (magick) is required." >&2
  exit 1
fi

mkdir -p "$ICONSET" "$MENUSET"

render() {
  magick -background none -density 384 "$SVG" \
    -resize "$(( $1 * 9 / 10 ))x$(( $1 * 9 / 10 ))" \
    -gravity center \
    -extent "${1}x${1}" \
    "$2"
}

render 16 "$ICONSET/icon_16x16.png"
render 32 "$ICONSET/icon_16x16@2x.png"
render 32 "$ICONSET/icon_32x32.png"
render 64 "$ICONSET/icon_32x32@2x.png"
render 128 "$ICONSET/icon_128x128.png"
render 256 "$ICONSET/icon_128x128@2x.png"
render 256 "$ICONSET/icon_256x256.png"
render 512 "$ICONSET/icon_256x256@2x.png"
render 512 "$ICONSET/icon_512x512.png"
render 1024 "$ICONSET/icon_512x512@2x.png"

render_menubar_template() {
  local size=$1
  local out=$2
  local inner=$(( size - 2 ))
  magick -background none -density 384 "$MENUBAR_SVG" \
    -resize "${inner}x${inner}" \
    -gravity center -extent "${size}x${size}" \
    "$out"
}

render_menubar_template 18 "$MENUSET/menubar@1x.png"
render_menubar_template 36 "$MENUSET/menubar@2x.png"

echo "Generated app and menu bar icons in Assets.xcassets"
