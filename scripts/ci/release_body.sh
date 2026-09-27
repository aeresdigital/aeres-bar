#!/bin/zsh
# CI: o texto da release no GitHub, com a instalação e as notas da versão.
#   scripts/ci/release_body.sh <notas.md> [notarizado: true|false]
set -euo pipefail

readonly NOTES="${1:?uso: scripts/ci/release_body.sh <notas.md> [true|false]}"
readonly NOTARIZED="${2:-false}"
readonly FEED="https://github.com/aeresdigital/aeres-bar-releases"

cat <<EOF
## Instalar

No Terminal (recomendado: o app abre sem o aviso do macOS e as próximas versões chegam pelo próprio app):

\`\`\`bash
curl -fsSL $FEED/releases/latest/download/install.sh | sh
\`\`\`

Ou baixe o **AERES-Bar.dmg** abaixo e arraste o AERES Bar para **Aplicativos**.
EOF
if [[ "$NOTARIZED" != "true" ]]; then
  print -r -- "Baixado pelo navegador, o macOS pede para liberar o app na primeira abertura: **Ajustes do Sistema › Privacidade e Segurança › Abrir Mesmo Assim** (no macOS 14, clique com o botão direito no app › **Abrir**)."
fi
cat <<EOF

Quem já tem o AERES Bar instalado recebe esta versão pelo próprio app.

## O que mudou

$(<"$NOTES")

---

Requer o macOS 14 ou mais recente (Apple Silicon ou Intel). Uso não comercial, nos termos da licença [PolyForm Noncommercial 1.0.0]($FEED/blob/main/LICENSE).
EOF
