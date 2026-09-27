#!/bin/zsh
# Remove o AERES Bar: desliga a abertura no login, encerra o app e apaga app, cache e preferências.
set -euo pipefail

readonly APP="/Applications/AERES Bar.app"
readonly BUNDLE_ID="com.aeresdigital.aeresbar"

if [[ -x "$APP/Contents/MacOS/AERESBar" ]]; then
  "$APP/Contents/MacOS/AERESBar" --login-item off || true
fi
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
pkill -x AERESBar 2>/dev/null || true

rm -rf "$APP" "$HOME/Library/Application Support/AERES Bar"
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
echo "✓ AERES Bar removido"
