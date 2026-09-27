#!/bin/zsh
# Imprime as notas de uma versão, geradas das mensagens de commit (Conventional Commits) desde a
# versão anterior (a última tag v*): as notas aparecem nas releases e no próprio app.
# Entra o que o usuário percebe (feat, fix, perf); o resto (docs, ci, test, refactor…) fica de fora.
#   scripts/release_notes.sh [commit]   (padrão: HEAD)
set -euo pipefail
cd "$(dirname "$0")/.."

readonly TARGET="${1:-HEAD}"
# From the parent, so a re-run of a version that already has its tag still finds the previous one.
previous="$(git describe --tags --abbrev=0 --match 'v[0-9]*' "$TARGET^" 2>/dev/null || true)"
range="${previous:+$previous..}$TARGET"

typeset -aU added fixed improved
while IFS= read -r subject; do
  [[ "$subject" =~ '^([a-z]+)(\([^)]*\))?!?: (.+)$' ]] || continue
  type="$match[1]"
  text="${match[3]% \(\#[0-9]*\)}"  # PR numbers point at the private repository
  text="${(U)text[1]}${text[2,-1]}"
  case "$type" in
    feat) added+=("$text") ;;
    fix) fixed+=("$text") ;;
    perf) improved+=("$text") ;;
  esac
done < <(git log --no-merges --format=%s "$range")

section() {
  local title="$1"
  shift
  (( $# > 0 )) || return 0
  print -r -- "### $title"
  print
  for item in "$@"; do print -r -- "- $item"; done
  print
}

notes="$(section Novidades "${added[@]}"; section Correções "${fixed[@]}"; section Melhorias "${improved[@]}")"
print -r -- "${notes:-- Ajustes internos, sem mudanças visíveis.}"
