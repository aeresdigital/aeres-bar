# Segurança

## Como o AERES Bar lida com credenciais

- **Só leitura.** O app lê as credenciais que o Claude Code, o Codex e o Antigravity já guardam. Ele não pede login, não guarda cópia e não renova tokens.
- **Destino restrito.** Cada credencial só é enviada ao servidor oficial do provedor que a emitiu, por HTTPS: `api.anthropic.com` e `chatgpt.com`. O token CSRF do Antigravity só vai para o próprio language server em `127.0.0.1`.
- **Nada em disco.** O cache (`~/Library/Application Support/AERES Bar/snapshots.json`) contém só números, datas e textos exibidos. Tokens nunca vão para o cache nem para os logs; os logs registram só o tipo de falha.
- **Chaves do macOS.** O item *Claude Code-credentials* é lido com `/usr/bin/security`, a mesma ferramenta com que o Claude Code o grava. Por isso não aparece pedido de acesso.
- **Certificado local.** O certificado autoassinado do language server do Antigravity é aceito apenas para `127.0.0.1`, `localhost` e `::1`.
- **Sem telemetria.** O app não se comunica com nenhum outro servidor.

## Relatando uma vulnerabilidade

Não abra uma issue pública. Use **Security › Report a vulnerability** no repositório (GitHub Security Advisories) ou escreva diretamente aos mantenedores da AERES Digital, com:

- descrição e impacto;
- passos para reproduzir;
- versão do AERES Bar e do macOS.

Respondemos em até 5 dias úteis.
