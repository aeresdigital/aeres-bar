#!/bin/zsh
# Imprime a seção do CHANGELOG.md de uma versão (usada como notas da release no GitHub).
#   scripts/release_notes.sh 1.0.0
set -euo pipefail
cd "$(dirname "$0")/.."

readonly VERSION="${1:?uso: scripts/release_notes.sh <versão>}"
notes="$(awk -v version="$VERSION" '
  $0 ~ "^## \\[" version "\\]" { printing = 1; next }
  printing && /^## \[/ { exit }
  printing { print }
' CHANGELOG.md)"

[[ -n "${notes//[[:space:]]/}" ]] || { echo "CHANGELOG.md não tem a seção [$VERSION]" >&2; exit 1; }
print -r -- "$notes"
