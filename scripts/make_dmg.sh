#!/bin/zsh
# Gera "dist/AERES-Bar.dmg" e o .sha256 ao lado: o app, um atalho para Aplicativos (arrastar e
# soltar) e um texto para quando o macOS bloquear a primeira abertura.
#   SIGN_IDENTITY="…"   assina também o .dmg (necessário para notarizar)
set -euo pipefail
cd "$(dirname "$0")/.."

readonly APP="dist/AERES Bar.app"
readonly DMG="dist/AERES-Bar.dmg"
readonly INSTALL_COMMAND="curl -fsSL https://github.com/aeresdigital/aeres-bar-releases/releases/latest/download/install.sh | sh"
[[ -d "$APP" ]] || ./scripts/build_app.sh

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
ditto "$APP" "$staging/AERES Bar.app"
ln -s /Applications "$staging/Aplicativos"
cat > "$staging/Se o macOS bloquear a abertura.txt" <<EOF
O AERES Bar não é notarizado pela Apple. Se, ao abrir, o macOS disser que não
pôde verificar o app ("Apple could not verify…"):

• Jeito recomendado: instale pelo Terminal. O app abre direto e as próximas
  versões chegam pelo próprio app:

  $INSTALL_COMMAND

• Ou abra mesmo assim. No macOS 15 ou mais recente: Ajustes do Sistema ›
  Privacidade e Segurança › Abrir Mesmo Assim. No macOS 14: clique com o
  botão direito no app › Abrir. Instalado assim, o macOS pode impedir as
  atualizações automáticas; nesse caso o próprio app avisa e mostra o
  comando acima.

Licença: uso não comercial (PolyForm Noncommercial 1.0.0). O texto fica em
AERES Bar.app › Contents › Resources › LICENSE e em
https://github.com/aeresdigital/aeres-bar-releases
EOF

rm -f "$DMG" "$DMG.sha256"
hdiutil create -volname "AERES Bar $VERSION" -srcfolder "$staging" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
hdiutil verify -quiet "$DMG"
if [[ "${SIGN_IDENTITY:--}" != "-" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi
(cd dist && shasum -a 256 AERES-Bar.dmg > AERES-Bar.dmg.sha256)

echo "✓ $DMG ($VERSION)"
