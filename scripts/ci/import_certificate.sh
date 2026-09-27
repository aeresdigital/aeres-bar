#!/bin/zsh
# CI: importa o certificado Developer ID num chaveiro temporário e exporta SIGN_IDENTITY.
#   MACOS_CERTIFICATE           .p12 em base64
#   MACOS_CERTIFICATE_PASSWORD  senha do .p12
set -euo pipefail
: "${MACOS_CERTIFICATE:?}" "${MACOS_CERTIFICATE_PASSWORD:?}" "${RUNNER_TEMP:?}" "${GITHUB_ENV:?}"

readonly KEYCHAIN="$RUNNER_TEMP/signing.keychain-db"
readonly CERTIFICATE="$RUNNER_TEMP/certificate.p12"
keychain_password="$(uuidgen)"

print -r -- "$MACOS_CERTIFICATE" | base64 --decode > "$CERTIFICATE"
security create-keychain -p "$keychain_password" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$keychain_password" "$KEYCHAIN"
security import "$CERTIFICATE" -P "$MACOS_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple: -k "$keychain_password" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" ${(f)"$(security list-keychains -d user | tr -d '" ')"}
rm -f "$CERTIFICATE"

identity="$(security find-identity -v -p codesigning "$KEYCHAIN" | awk -F'"' '/Developer ID Application/ { print $2; exit }')"
[[ -n "$identity" ]] || { echo "nenhuma identidade Developer ID Application no certificado" >&2; exit 1; }
echo "SIGN_IDENTITY=$identity" >> "$GITHUB_ENV"
echo "✓ identidade de assinatura importada"
