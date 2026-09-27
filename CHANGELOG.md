# Changelog

Todas as mudanças relevantes do AERES Bar. O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e o projeto usa [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [Não publicado]

### Adicionado

- GitHub Copilot: cotas do mês (requisições premium, chat e autocompletar) e plano, pela API do GitHub, com o login do GitHub CLI ou dos plugins do Copilot.
- Ollama: limites de sessão (5 h) e semanal do Ollama Cloud, com a chave da API, e o servidor local com a versão e os modelos carregados.
- OpenRouter: limite de gasto da chave (diário, semanal, mensal ou fixo), cota diária de modelos gratuitos, gasto do dia, da semana e do mês e saldo de créditos (com chave de gerenciamento).
- Chaves de API do OpenRouter e do Ollama Cloud no menu de ajustes (definir, trocar, remover e criar no site) e na linha de comando (`--set-key`, `--delete-key`), guardadas no Chaves do macOS.
- Menu **Provedores** para ligar e desligar cada provedor, e rodapé no painel com os que faltam configurar.
- Ajustes **Ícone na barra** (medidores ou logo do mais crítico) e **Mostrar o número ao lado do ícone**.

### Alterado

- Um único item na barra de menus, no lugar de um por provedor: um medidor com uma barra por provedor e a porcentagem do mais perto do limite. Ao passar o mouse, o painel mostra todos os provedores de uma vez; clicar num provedor abre os detalhes dele.
- **Atualizar agora** consulta as APIs na hora em vez de reaproveitar a resposta recente, respeitando um intervalo mínimo de 15 s e as pausas pedidas pelos provedores.
- Os tokens de hoje, quando escolhidos como número da barra, somam todos os provedores.

### Corrigido

- O botão de atualizar do painel girava de forma errática e parecia não fazer nada; agora mostra um indicador de progresso enquanto atualiza.
- A API de uso da Anthropic é consultada no máximo a cada 3 min nas atualizações automáticas, evitando o HTTP 429.

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
