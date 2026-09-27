# Changelog

Todas as mudanças relevantes do AERES Bar. O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e o projeto usa [Versionamento Semântico](https://semver.org/lang/pt-BR/).

Cada merge na `main` que muda o app vira uma versão publicada automaticamente: `MAJOR.MINOR` do arquivo `VERSION` mais o número do build (`1.0.23`). As notas de cada versão, geradas das mensagens de commit, ficam nas [Releases](https://github.com/aeresdigital/aeres-bar-releases/releases) e aparecem no próprio app. Este arquivo resume cada série (`1.0`, `1.1`…): ao mudar `VERSION`, abra uma seção nova.

## [1.0] - publicação contínua, desde 2026-09-27

### Adicionado

- Versões publicadas a cada merge na `main`, no repositório público [aeresdigital/aeres-bar-releases](https://github.com/aeresdigital/aeres-bar-releases): DMG, instalador pelo Terminal (`curl … | sh`, sem o aviso de quarentena do macOS) e o pacote de atualização assinado.
- Atualização pelo próprio app: procura ao abrir, a cada hora e em **Procurar atualizações…**; a versão nova aparece no topo do painel e no menu, e um clique baixa, confere a assinatura Ed25519 e a de código, troca o app e o abre de novo. Se a troca falhar, a versão anterior volta.
- `--check-update` na linha de comando: compara a versão instalada com a publicada.
- Licença [PolyForm Noncommercial 1.0.0](LICENSE) (uso não comercial) e os avisos de terceiros das marcas ([THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)), que também vão dentro do app.
- Modelos chineses, cada um pela fonte mais confiável que existe:
  - **GLM (Z.ai / Zhipu):** sessão de 5 h, semana e cota mensal de ferramentas MCP do GLM Coding Plan.
  - **Kimi Code:** sessão de 5 h, semana e mês da assinatura, com o login do Kimi Code CLI ou uma chave do console.
  - **Kimi API:** saldo da plataforma aberta, em dólar ou yuan.
  - **MiniMax:** sessão de 5 h e semana do Token Plan.
  - **DeepSeek:** saldo recarregado e de bônus.
  - **Qwen (Model Studio)** e **Doubao (Volcengine):** Coding Plan pelos CLIs oficiais (`bl` e `arkcli`) e o login deles.
- Detecção da região (internacional ou China continental) de cada chave, e reaproveitamento das chaves que o Claude Code, o Codex e os CLIs oficiais já têm, só para leitura.
- Chaves das plataformas chinesas no menu **Chaves de API** e no `--set-key` (`glm`, `kimi-code`, `moonshot`, `minimax`, `deepseek`).
- GitHub Copilot: cotas do mês (requisições premium, chat e autocompletar) e plano, pela API do GitHub, com o login do GitHub CLI ou dos plugins do Copilot.
- Ollama: limites de sessão (5 h) e semanal do Ollama Cloud, com a chave da API, e o servidor local com a versão e os modelos carregados.
- OpenRouter: limite de gasto da chave (diário, semanal, mensal ou fixo), cota diária de modelos gratuitos, gasto do dia, da semana e do mês e saldo de créditos (com chave de gerenciamento).
- Chaves de API do OpenRouter e do Ollama Cloud no menu de ajustes (definir, trocar, remover e criar no site) e na linha de comando (`--set-key`, `--delete-key`), guardadas no Chaves do macOS.
- Resumo no topo do painel com um anel por provedor, no estilo do Apple Watch: logo no centro, porcentagem embaixo e cor pelo nível de alerta. Clicar num anel abre os detalhes do provedor.
- Menu **Provedores** para ligar e desligar cada provedor, e rodapé no painel com os que faltam configurar.
- Ajustes **Ícone na barra** (medidores ou logo do mais crítico) e **Mostrar o número ao lado do ícone**.

### Alterado

- A versão passa a ser `MAJOR.MINOR` (arquivo `VERSION`) mais o número do build; o DMG passa a se chamar `AERES-Bar.dmg` e traz o atalho **Aplicativos** e um texto para quando o macOS bloquear a primeira abertura.
- A licença deixa de ser proprietária: o app pode ser usado e distribuído para fins não comerciais.
- O resumo em anéis quebra em linhas de até seis, o painel rola abaixo do cabeçalho quando não cabe na tela, o medidor da barra alarga com mais de seis provedores e o rodapé cita até três provedores não configurados.
- Um único item na barra de menus, no lugar de um por provedor: um medidor com uma barra por provedor e a porcentagem do mais perto do limite. Ao passar o mouse, o painel mostra todos os provedores de uma vez; clicar num provedor abre os detalhes dele.
- **Atualizar agora** consulta as APIs na hora em vez de reaproveitar a resposta recente, respeitando um intervalo mínimo de 15 s e as pausas pedidas pelos provedores.
- Os tokens de hoje, quando escolhidos como número da barra, somam todos os provedores.

### Corrigido

- O botão de atualizar do painel girava de forma errática e parecia não fazer nada; agora mostra um indicador de progresso enquanto atualiza.
- A API de uso da Anthropic é consultada no máximo a cada 3 min nas atualizações automáticas, evitando o HTTP 429.
- A primeira leitura dos logs chegava a 1,7 GB de memória, e o app ficava com ~120 MB em repouso. Agora o pico é de ~115 MB e o repouso, ~26 MB.
- `make uninstall` também apaga as chaves de API guardadas no Chaves.

## 1.0.0 - 2026-09-27 (primeira versão, antes da publicação contínua)

### Adicionado

- Itens na barra de menus para Claude Code, Codex e Antigravity, com as marcas oficiais em versão monocromática e o limite mais crítico ao lado.
- Painel ao passar o mouse com todas as janelas de limite, contagem regressiva e horário de renovação, tokens de sessão, dia e semana, plano, uso extra e cota por modelo.
- Clique para fixar o painel e clique direito para os ajustes: provedores visíveis, número exibido, % restante, contagem regressiva na barra, cores de alerta, intervalo de atualização e abertura no login.
- Claude Code: limites pela API de uso da Anthropic (sessão de 5 h, semanal, semanal por modelo, uso extra, divisão por produto) e tokens pelas transcrições locais.
- Codex: limites pela API do ChatGPT, com o último limite registrado nos rollouts como plano B, e tokens pelos rollouts locais.
- Antigravity: cotas por grupo de modelos e por modelo pelo language server local, com atualização automática quando o app abre ou fecha.
- Cache em disco das últimas leituras, reaproveitamento de respostas recentes e respeito ao `Retry-After` das APIs.
- Linha de comando: `--dump`, `--render-preview [--demo]`, `--login-item on|off|status`, `--version`.
- CI no GitHub Actions (lint, build sem avisos, testes, cobertura mínima) e release com assinatura e notarização opcionais.

[1.0]: https://github.com/aeresdigital/aeres-bar-releases/releases
