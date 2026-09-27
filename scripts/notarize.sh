#!/bin/zsh
# Envia um .dmg assinado com Developer ID para notarização da Apple e grampeia o ticket.
# Credenciais da App Store Connect API (variáveis de ambiente):
#   NOTARY_KEY_ID, NOTARY_ISSUER_ID e NOTARY_KEY (conteúdo do arquivo .p8)
set -euo pipefail

readonly TARGET="${1:?uso: scripts/notarize.sh <arquivo.dmg>}"
: "${NOTARY_KEY_ID:?defina NOTARY_KEY_ID}" "${NOTARY_ISSUER_ID:?defina NOTARY_ISSUER_ID}" "${NOTARY_KEY:?defina NOTARY_KEY}"

key_file="$(mktemp -t notary-key).p8"
trap 'rm -f "$key_file"' EXIT
print -r -- "$NOTARY_KEY" > "$key_file"

xcrun notarytool submit "$TARGET" \
  --key "$key_file" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" \
  --wait --timeout 30m
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
echo "✓ $TARGET notarizado"
