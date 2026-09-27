#!/bin/zsh
# Remove o AERES Bar: desliga a abertura no login, encerra o app e apaga app, cache, preferências
# e as chaves de API que ele guardou no Chaves.
set -euo pipefail

readonly APP="/Applications/AERES Bar.app"
readonly BUNDLE_ID="com.aeresdigital.aeresbar"
readonly KEYCHAIN_SERVICE="AERES Bar"

if [[ -x "$APP/Contents/MacOS/AERESBar" ]]; then
  "$APP/Contents/MacOS/AERESBar" --login-item off || true
fi
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
pkill -x AERESBar 2>/dev/null || true

rm -rf "$APP" "$HOME/Library/Application Support/AERES Bar"
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
for account in openrouter ollama; do
  security delete-generic-password -s "$KEYCHAIN_SERVICE" -a "$account" >/dev/null 2>&1 || true
done
echo "✓ AERES Bar removido"
