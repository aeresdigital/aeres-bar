#!/bin/zsh
# Gera "dist/AERES-Bar-<versão>.dmg" (arrastar para Aplicativos) e o arquivo .sha256 ao lado.
#   SIGN_IDENTITY="…"   assina também o .dmg (necessário para notarizar)
set -euo pipefail
cd "$(dirname "$0")/.."

readonly APP="dist/AERES Bar.app"
[[ -d "$APP" ]] || ./scripts/build_app.sh

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
readonly DMG="dist/AERES-Bar-$VERSION.dmg"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/AERES Bar"
ditto "$APP" "$staging/AERES Bar/AERES Bar.app"
ln -s /Applications "$staging/AERES Bar/Applications"

rm -f "$DMG" "$DMG.sha256"
hdiutil create -volname "AERES Bar" -srcfolder "$staging/AERES Bar" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
if [[ "${SIGN_IDENTITY:--}" != "-" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi
(cd dist && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")

echo "✓ $DMG"
