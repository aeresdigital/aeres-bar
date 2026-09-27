#!/bin/zsh
# Compila, instala em /Applications e abre o AERES Bar (substitui uma versão anterior).
set -euo pipefail
cd "$(dirname "$0")/.."

readonly DEST="/Applications/AERES Bar.app"
readonly BUNDLE_ID="com.aeresdigital.aeresbar"

./scripts/build_app.sh

if pgrep -x AERESBar >/dev/null; then
  echo "→ Encerrando a versão em execução…"
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  for _ in {1..20}; do pgrep -x AERESBar >/dev/null || break; sleep 0.25; done
  pkill -x AERESBar 2>/dev/null || true
fi

echo "→ Instalando em $DEST…"
rm -rf "$DEST"
ditto "dist/AERES Bar.app" "$DEST"
open "$DEST"
echo "✓ AERES Bar instalado. Ele aparece na barra de menus."
