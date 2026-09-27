#!/bin/zsh
# Mede a cobertura de linhas por módulo e falha se ficar abaixo do mínimo.
#
#   scripts/coverage.sh            roda os testes com cobertura e mede
#   SKIP_TESTS=1 scripts/coverage.sh   só mede (os testes já rodaram com --enable-code-coverage)
#
# Mínimos (sobrescreva por variável de ambiente):
#   CORE_MIN=85  domínio, provedores e estado — tudo testável sem interface
#   UI_MIN=60    marcas e views; a cola com AppKit (itens da barra, janela) exige sessão gráfica
set -euo pipefail
cd "$(dirname "$0")/.."

CORE_MIN="${CORE_MIN:-85}"
UI_MIN="${UI_MIN:-60}"

if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
  swift test --enable-code-coverage
fi

BIN_PATH="$(swift build --show-bin-path)"
PROFDATA="$(dirname "$(swift test --show-codecov-path)")/default.profdata"
[[ -f "$PROFDATA" ]] || { echo "profdata não encontrado em $PROFDATA" >&2; exit 1; }

# SwiftPM gera um bundle por alvo de teste (swift-build) ou um único "<Pacote>PackageTests".
objects=()
for bundle in "$BIN_PATH"/*.xctest(N); do
  name="$(basename "$bundle" .xctest)"
  [[ -f "$bundle/Contents/MacOS/$name" ]] && objects+=("$bundle/Contents/MacOS/$name")
done
(( ${#objects} > 0 )) || { echo "nenhum binário de teste em $BIN_PATH" >&2; exit 1; }
args=("${objects[1]}")
for object in "${objects[@]:1}"; do args+=(-object "$object"); done

line_coverage() {
  xcrun llvm-cov report "${args[@]}" -instr-profile "$PROFDATA" "$PWD/Sources/$1" | awk '/^TOTAL/ { gsub("%", "", $10); print $10 }'
}

mkdir -p .build/coverage
xcrun llvm-cov export "${args[@]}" -instr-profile "$PROFDATA" -format=lcov \
  -ignore-filename-regex='(\.build|Tests)/' > .build/coverage/coverage.lcov

core="$(line_coverage AERESBarCore)"
ui="$(line_coverage AERESBarUI)"

summary="$(cat <<EOF
### Cobertura de testes (linhas)

| Módulo | Cobertura | Mínimo |
| --- | ---: | ---: |
| AERESBarCore | ${core}% | ${CORE_MIN}% |
| AERESBarUI | ${ui}% | ${UI_MIN}% |
EOF
)"
echo "$summary"
[[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && echo "$summary" >> "$GITHUB_STEP_SUMMARY"

failed=0
if (( core < CORE_MIN )); then echo "✗ AERESBarCore abaixo do mínimo" >&2; failed=1; fi
if (( ui < UI_MIN )); then echo "✗ AERESBarUI abaixo do mínimo" >&2; failed=1; fi
exit $failed
