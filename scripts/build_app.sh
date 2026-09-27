#!/bin/zsh
# Compila o AERES Bar e monta "dist/AERES Bar.app", com a licença e os avisos de terceiros.
#
# A versão é MAJOR.MINOR (arquivo VERSION) mais o número do build, que é a quantidade de commits:
# na main ele só cresce, e é o que o app compara para saber se há uma versão nova.
#
#   UNIVERSAL=1          binário arm64 + x86_64
#   BUILD_NUMBER=42      número do build (padrão: quantidade de commits)
#   VERSION=1.2.3        versão completa (padrão: VERSION + número do build)
#   SIGN_IDENTITY="…"    identidade Developer ID; sem ela, assinatura ad-hoc
set -euo pipefail
cd "$(dirname "$0")/.."

readonly APP_NAME="AERES Bar"
readonly EXECUTABLE="AERESBar"
readonly BUNDLE_ID="com.aeresdigital.aeresbar"
readonly APP="dist/$APP_NAME.app"
SERIES="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
VERSION="${VERSION:-$SERIES.$BUILD_NUMBER}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

[[ "$SERIES" =~ '^[0-9]+\.[0-9]+$' ]] || { echo "o arquivo VERSION deve ter MAJOR.MINOR (ex.: 1.0): $SERIES" >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ '^[0-9]+$' ]] || { echo "número do build inválido: $BUILD_NUMBER" >&2; exit 1; }
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { echo "versão inválida: $VERSION" >&2; exit 1; }

build_flags=(-c release --product "$EXECUTABLE")
[[ "${UNIVERSAL:-0}" == "1" ]] && build_flags+=(--arch arm64 --arch x86_64)

echo "→ Compilando $APP_NAME $VERSION ($BUILD_NUMBER)…"
swift build "${build_flags[@]}"
BIN_DIR="$(swift build "${build_flags[@]}" --show-bin-path)"

echo "→ Montando $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp LICENSE THIRD-PARTY-NOTICES.md "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleShortVersionString $VERSION" \
  -c "Set :CFBundleVersion $BUILD_NUMBER" \
  "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "→ Assinando ($([[ "$SIGN_IDENTITY" == "-" ]] && echo ad-hoc || echo "$SIGN_IDENTITY"))…"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
else
  codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" --options runtime --timestamp "$APP"
fi
codesign --verify --strict "$APP"

echo "✓ $APP ($(lipo -archs "$APP/Contents/MacOS/$EXECUTABLE"))"
