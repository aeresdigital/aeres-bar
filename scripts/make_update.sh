#!/bin/zsh
# Empacota "dist/AERES Bar.app" para a atualização pelo próprio app: "dist/AERES-Bar.zip", o
# .sha256 e "dist/update.json", que os apps instalados leem para oferecer a versão nova.
#
#   UPDATE_SIGNING_KEY=<base64> scripts/make_update.sh <notas.md> <url-do-zip>
#
# O update.json leva a assinatura Ed25519 do zip: o app só instala um zip cuja assinatura confere
# com a chave pública compilada nele (UpdateFeed.publicKey).
set -euo pipefail
cd "$(dirname "$0")/.."

readonly USAGE="uso: scripts/make_update.sh <notas.md> <url-do-zip>"
readonly NOTES="${1:?$USAGE}"
readonly URL="${2:?$USAGE}"
readonly APP="dist/AERES Bar.app"
readonly ZIP="dist/AERES-Bar.zip"
: "${UPDATE_SIGNING_KEY:?defina UPDATE_SIGNING_KEY (a chave privada, em base64)}"
[[ -d "$APP" ]] || { echo "falta $APP: rode scripts/build_app.sh" >&2; exit 1; }
[[ -f "$NOTES" ]] || { echo "notas não encontradas: $NOTES" >&2; exit 1; }

plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist"; }
readonly VERSION="$(plist CFBundleShortVersionString)"
readonly BUILD="$(plist CFBundleVersion)"
readonly MINIMUM="$(plist LSMinimumSystemVersion)"

rm -f "$ZIP" "$ZIP.sha256" dist/update.json
ditto -c -k --keepParent "$APP" "$ZIP"
(cd dist && shasum -a 256 AERES-Bar.zip > AERES-Bar.zip.sha256)
signature="$(swift scripts/sign_update.swift "$ZIP")"

jq -n \
  --arg version "$VERSION" \
  --argjson build "$BUILD" \
  --rawfile notes "$NOTES" \
  --arg url "$URL" \
  --arg signature "$signature" \
  --arg minimum "$MINIMUM" \
  '{version: $version, build: $build, notes: $notes, url: $url, signature: $signature, minimumSystemVersion: $minimum}' \
  > dist/update.json

echo "✓ $ZIP e dist/update.json ($VERSION, build $BUILD)"
