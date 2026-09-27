# Segurança

## Como o AERES Bar lida com credenciais

- **Logins só lidos.** O app lê as credenciais que o Claude Code, o Codex, o Antigravity e o GitHub CLI (ou os plugins do Copilot) já guardam. Ele não faz login, não guarda cópia e não renova tokens.
- **Chaves de API só quando você as dá.** O OpenRouter e o Ollama Cloud não têm login local; a chave que você informa fica no Chaves do macOS (serviço *AERES Bar*). Ela é gravada pelo `/usr/bin/security` recebendo o comando pela entrada padrão, nunca como argumento de linha de comando, que outros processos poderiam listar. Chaves com espaços, aspas ou barras invertidas são recusadas antes de chegar ao `security`.
- **Destino restrito.** Cada credencial só é enviada ao servidor oficial do provedor, por HTTPS: `api.anthropic.com`, `chatgpt.com`, `api.github.com`, `ollama.com` e `openrouter.ai`. O token CSRF do Antigravity só vai para o próprio language server em `127.0.0.1`, e o servidor local do Ollama é consultado sem credencial.
- **Nada em disco.** O cache (`~/Library/Application Support/AERES Bar/snapshots.json`) contém só números, datas e textos exibidos. Tokens e chaves nunca vão para o cache nem para os logs; os logs registram só o tipo de falha.
- **Chaves do macOS.** Os itens do Chaves são lidos com `/usr/bin/security`, a mesma ferramenta com que o Claude Code grava o seu. Por isso não aparece pedido de acesso, nem depois de uma atualização do app.
- **Certificado local.** O certificado autoassinado do language server do Antigravity é aceito apenas para `127.0.0.1`, `localhost` e `::1`.
- **Sem telemetria.** O app não se comunica com nenhum outro servidor.

## Relatando uma vulnerabilidade

Não abra uma issue pública. Use **Security › Report a vulnerability** no repositório (GitHub Security Advisories) ou escreva diretamente aos mantenedores da AERES Digital, com:

- descrição e impacto;
- passos para reproduzir;
- versão do AERES Bar e do macOS.

Respondemos em até 5 dias úteis.
