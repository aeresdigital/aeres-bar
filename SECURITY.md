# Segurança

## Como o AERES Bar lida com credenciais

- **Logins só lidos.** O app lê as credenciais que o Claude Code, o Codex, o Antigravity e o GitHub CLI (ou os plugins do Copilot) já guardam, e os logins dos CLIs oficiais do Kimi Code e do MiniMax. Ele não faz login, não guarda cópia e não renova tokens.
- **Chaves de outras ferramentas, com critério.** A chave que o Claude Code usa para um provedor terceiro (`ANTHROPIC_AUTH_TOKEN` em `~/.claude/settings.json`) só é lida quando o `ANTHROPIC_BASE_URL` de lá aponta para aquele provedor (host exato ou subdomínio), e só é enviada a ele. O mesmo vale para a chave do DeepSeek no `config.toml` do Codex e para a do Coding Tool Helper do Z.ai.
- **CLIs oficiais.** O Qwen e o Doubao são lidos rodando os CLIs oficiais (`bl` do Model Studio e `arkcli` do Volcengine) com o login deles. O app só roda um CLI se a pasta de login dele existir e nunca pede a AccessKey/SecretKey da conta, que dá acesso a tudo.
- **Chaves de API só quando você as dá.** O OpenRouter, o Ollama Cloud e as plataformas chinesas (GLM, Kimi, MiniMax, DeepSeek) não têm login local reaproveitável; a chave que você informa fica no Chaves do macOS (serviço *AERES Bar*). Ela é gravada pelo `/usr/bin/security` recebendo o comando pela entrada padrão, nunca como argumento de linha de comando, que outros processos poderiam listar. Chaves com espaços, aspas ou barras invertidas são recusadas antes de chegar ao `security`.
- **Destino restrito.** Cada credencial só é enviada ao servidor oficial do provedor, por HTTPS: `api.anthropic.com`, `chatgpt.com`, `api.github.com`, `ollama.com`, `openrouter.ai`, `api.z.ai` / `open.bigmodel.cn`, `api.kimi.ai` / `api.kimi.com`, `api.moonshot.ai` / `api.moonshot.cn`, `api.minimax.io` / `api.minimaxi.com` e `api.deepseek.com`. As plataformas chinesas têm um host por região e a chave é tentada nos dois hosts do mesmo provedor, nunca em outro. O token CSRF do Antigravity só vai para o próprio language server em `127.0.0.1`, e o servidor local do Ollama é consultado sem credencial.
- **Nada em disco.** O cache (`~/Library/Application Support/AERES Bar/snapshots.json`) contém só números, datas e textos exibidos. Tokens e chaves nunca vão para o cache nem para os logs; os logs registram só o tipo de falha.
- **Chaves do macOS.** Os itens do Chaves são lidos com `/usr/bin/security`, a mesma ferramenta com que o Claude Code grava o seu. Por isso não aparece pedido de acesso, nem depois de uma atualização do app.
- **Certificado local.** O certificado autoassinado do language server do Antigravity é aceito apenas para `127.0.0.1`, `localhost` e `::1`.
- **Sem telemetria.** Além dos provedores, o app só fala com o GitHub, para as atualizações (abaixo), sem enviar nada seu.

## Atualizações

- **De onde vêm:** do repositório público [aeresdigital/aeres-bar-releases](https://github.com/aeresdigital/aeres-bar-releases), que só tem as versões publicadas pelo workflow de release. O app lê `releases/latest/download/update.json` em `github.com` e, quando você aceita, baixa o zip indicado ali. O zip precisa estar no mesmo endereço de origem do `update.json`: um `update.json` adulterado não consegue mandar o app baixar de outro lugar.
- **Assinatura:** cada zip é assinado com Ed25519 no CI (`scripts/sign_update.swift`, segredo `UPDATE_SIGNING_KEY`). O app só instala se a assinatura conferir com a chave pública compilada nele (`UpdateFeed.publicKey`). Quem conseguir publicar no repositório de releases, ou trocar arquivos lá, ainda não consegue entregar código aos usuários sem a chave privada.
- **Conferências antes de trocar:** o app descompacta a versão ao lado da instalada, confere o identificador (`com.aeresdigital.aeresbar`), se o número do build é o anunciado e maior que o instalado (sem voltar para versões antigas) e a assinatura de código (`codesign --verify --strict`).
- **Troca:** um ajudante (`/bin/sh`, com os caminhos passados como argumentos, nunca dentro do texto do script) espera o app fechar, troca os apps e, se algo falhar, põe a versão anterior de volta e deixa um aviso para a próxima abertura.
- **Quarentena:** um arquivo que o próprio app baixa não recebe a marca de quarentena, por isso a versão nova abre sem o aviso do Gatekeeper. É exatamente por isso que nada é instalado sem a assinatura conferir.
- **Instalação pelo Terminal:** o `install.sh` publicado em cada versão baixa o zip por HTTPS, confere o checksum e a assinatura de código, e só então substitui o app. Ele vem do mesmo repositório de releases, então confia nele como confiaria no DMG.

## Relatando uma vulnerabilidade

Não abra uma issue pública. Use **Security › Report a vulnerability** no repositório (GitHub Security Advisories) ou escreva diretamente aos mantenedores da AERES Digital, com:

- descrição e impacto;
- passos para reproduzir;
- versão do AERES Bar e do macOS.

Respondemos em até 5 dias úteis.
