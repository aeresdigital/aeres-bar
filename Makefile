SHELL := /bin/zsh
SWIFT_FORMAT := swift run -c release --package-path BuildTools swift-format
LINT_PATHS := Package.swift BuildTools/Package.swift Sources Tests scripts/make_icon.swift scripts/sign_update.swift

.DEFAULT_GOAL := help
.PHONY: help build test coverage format lint check app dmg install uninstall run dump preview icon docs-images clean

help: ## Lista os comandos
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{ printf "  \033[1m%-12s\033[0m %s\n", $$1, $$2 }'

build: ## Compila (debug), tratando avisos como erros
	swift build -Xswiftc -warnings-as-errors

test: ## Roda todos os testes
	swift test

coverage: ## Testes com cobertura e verificação dos mínimos
	./scripts/coverage.sh

format: ## Formata o código com o swift-format fixado em BuildTools
	$(SWIFT_FORMAT) format --in-place --parallel --recursive $(LINT_PATHS)

lint: ## Verifica estilo e regras (mesmo comando do CI)
	$(SWIFT_FORMAT) lint --strict --parallel --recursive $(LINT_PATHS)

check: lint build coverage ## Tudo o que o CI verifica

app: ## Gera "dist/AERES Bar.app" (UNIVERSAL=1 para arm64 + x86_64)
	./scripts/build_app.sh

dmg: app ## Gera o .dmg e o checksum em dist/
	./scripts/make_dmg.sh

install: ## Compila e instala em /Applications
	./scripts/install.sh

uninstall: ## Remove o app, o cache e as preferências
	./scripts/uninstall.sh

run: ## Roda o app a partir do código (sem instalar)
	swift run AERESBar

dump: ## Mostra em JSON tudo o que o app lê
	swift run -c release AERESBar --dump

preview: ## Salva imagens do painel e da barra em ./preview
	swift run -c release AERESBar --render-preview preview

docs-images: ## Atualiza as imagens do README (dados de exemplo) em docs/images
	swift run -c release AERESBar --render-preview docs/images --demo
	sips -s format png -Z 256 Resources/AppIcon.icns --out docs/images/icon.png >/dev/null

icon: ## Regera Resources/AppIcon.icns
	@tmp="$$(mktemp -d)/AppIcon.iconset" && swift scripts/make_icon.swift "$$tmp" && iconutil -c icns "$$tmp" -o Resources/AppIcon.icns

clean: ## Apaga artefatos de build
	rm -rf .build dist preview
