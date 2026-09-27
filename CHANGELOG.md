# Changelog

Todas as mudanças relevantes do AERES Bar. O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e o projeto usa [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [Não publicado]

## [1.0.0] - 2026-09-27

### Adicionado

- Itens na barra de menus para Claude Code, Codex e Antigravity, com as marcas oficiais em versão monocromática e o limite mais crítico ao lado.
- Painel ao passar o mouse com todas as janelas de limite, contagem regressiva e horário de renovação, tokens de sessão, dia e semana, plano, uso extra e cota por modelo.
- Clique para fixar o painel e clique direito para os ajustes: provedores visíveis, número exibido, % restante, contagem regressiva na barra, cores de alerta, intervalo de atualização e abertura no login.
- Claude Code: limites pela API de uso da Anthropic (sessão de 5 h, semanal, semanal por modelo, uso extra, divisão por produto) e tokens pelas transcrições locais.
- Codex: limites pela API do ChatGPT, com o último limite registrado nos rollouts como plano B, e tokens pelos rollouts locais.
- Antigravity: cotas por grupo de modelos e por modelo pelo language server local, com atualização automática quando o app abre ou fecha.
- Cache em disco das últimas leituras, reaproveitamento de respostas recentes e respeito ao `Retry-After` das APIs.
- Linha de comando: `--dump`, `--render-preview [--demo]`, `--login-item on|off|status`, `--version`.
- CI no GitHub Actions (lint, build sem avisos, testes, cobertura mínima, DMG de desenvolvimento) e release automatizada por tag, com assinatura e notarização opcionais.

[Não publicado]: https://github.com/aeresdigital/aeres-bar/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/aeresdigital/aeres-bar/releases/tag/v1.0.0
