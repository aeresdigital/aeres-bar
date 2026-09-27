#!/bin/sh
# Instala (ou reinstala) a versão mais recente do AERES Bar a partir das releases públicas.
# Publicado em cada release como install.sh:
#
#   curl -fsSL https://github.com/aeresdigital/aeres-bar-releases/releases/latest/download/install.sh | sh
#
# Baixado pelo curl, o app não recebe a marca de quarentena que o navegador coloca: abre sem o
# aviso "Apple could not verify…" e as próximas versões chegam pelo próprio app. Preferências,
# chaves de API e cache ficam como estão.
#
# A cópia instalada é reconhecida pelo identificador do app, não pelo nome.
# AERES_BAR_INSTALL_DIR troca a pasta de destino (padrão /Applications), AERES_BAR_NO_OPEN=1 não
# abre o app no fim e AERES_BAR_FEED troca o endereço das releases (testes).
set -eu

FEED="${AERES_BAR_FEED:-https://github.com/aeresdigital/aeres-bar-releases/releases/latest/download}"
BUNDLE_ID="com.aeresdigital.aeresbar"
NAME="AERES Bar"
EXECUTABLE="AERESBar"
ZIP="AERES-Bar.zip"
DEST_DIR="${AERES_BAR_INSTALL_DIR:-/Applications}"
APP="$DEST_DIR/$NAME.app"

fail() {
  echo "Erro: $1" >&2
  exit 1
}

[ "$(uname -s)" = Darwin ] || fail "o $NAME é um app para macOS."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 14 ] || fail "o $NAME precisa do macOS 14 ou mais recente."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

echo "==> Baixando a versão mais recente do $NAME…"
curl -fL --progress-bar -o "$work/$ZIP" "$FEED/$ZIP" || fail "não foi possível baixar o $NAME."
curl -fsSL -o "$work/$ZIP.sha256" "$FEED/$ZIP.sha256" || fail "não foi possível baixar o checksum."
expected=$(awk '{print $1}' "$work/$ZIP.sha256")
actual=$(shasum -a 256 "$work/$ZIP" | awk '{print $1}')
[ "$expected" = "$actual" ] || fail "o arquivo baixado não confere com o checksum. Nada foi instalado."

ditto -x -k "$work/$ZIP" "$work/new" || fail "não foi possível descompactar o pacote."
[ -d "$work/new/$NAME.app" ] || fail "o pacote não contém o $NAME.app."
codesign --verify --strict "$work/new/$NAME.app" 2>/dev/null || fail "o app baixado está corrompido. Nada foi instalado."

# Every copy of the app in the destination, whatever it is called.
installed() {
  for candidate in "$DEST_DIR"/*.app; do
    [ -d "$candidate" ] || continue
    id=$(defaults read "$candidate/Contents/Info" CFBundleIdentifier 2>/dev/null || true)
    [ "$id" = "$BUNDLE_ID" ] && printf '%s\n' "$candidate"
  done
  return 0
}

# The app keeps nothing but its settings, which live outside the bundle: it can simply be stopped.
if pgrep -x "$EXECUTABLE" >/dev/null 2>&1; then
  echo "==> Fechando o $NAME…"
  pkill -x "$EXECUTABLE" 2>/dev/null || true
  n=0
  while pgrep -x "$EXECUTABLE" >/dev/null 2>&1; do
    n=$((n + 1))
    [ "$n" -gt 40 ] && fail "o $NAME não fechou. Feche o app e rode o comando de novo."
    sleep 0.25
  done
fi

mkdir -p "$DEST_DIR"
installed | while IFS= read -r copy; do
  echo "==> Substituindo $copy…"
  # A copy installed from a browser download is protected by macOS: only Finder may remove it,
  # and it goes to the Trash, where it can be recovered.
  if touch "$copy/Contents/.aeres-bar-install" 2>/dev/null; then
    rm -f "$copy/Contents/.aeres-bar-install"
    rm -rf "$copy"
  else
    osascript -e "tell application \"Finder\" to delete (POSIX file \"$copy\" as alias)" >/dev/null 2>&1 \
      || fail "o macOS não deixou substituir o $NAME. Arraste o app da pasta Aplicativos para o Lixo e rode o comando de novo."
  fi
done

ditto "$work/new/$NAME.app" "$APP" || fail "não foi possível copiar o $NAME para $DEST_DIR."
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

version=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "")
echo "==> $NAME $version instalado em $DEST_DIR."
if [ -z "${AERES_BAR_NO_OPEN:-}" ]; then
  open "$APP"
fi
