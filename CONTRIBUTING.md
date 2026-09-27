# Contribuindo com o AERES Bar

## Fluxo

1. Crie um branch a partir da `main` (`feat/…`, `fix/…`, `docs/…`).
2. Faça as mudanças com testes. Toda lógica nova no `AERESBarCore` precisa de teste.
3. Rode `make check` (lint, build sem avisos, testes e cobertura) antes de abrir o PR.
4. Abra o PR preenchendo o template. O CI precisa passar e o PR precisa de revisão do CODEOWNER.
5. Faça o merge com *squash*, mantendo a mensagem no padrão Conventional Commits.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/pt-br/):

| Prefixo | Uso |
| --- | --- |
| `feat:` | funcionalidade nova |
| `fix:` | correção |
| `perf:` | desempenho |
| `refactor:` | mudança interna sem efeito visível |
| `test:` | testes |
| `docs:` | documentação |
| `ci:` / `build:` | pipeline e empacotamento |
| `chore:` | manutenção, releases |

## Código

- Swift 6 em modo de linguagem 6. O build não pode ter avisos (`make build` os trata como erros).
- Estilo definido pelo `.swift-format` e verificado com o `swift-format` fixado em `BuildTools` (`make format` corrige, `make lint` verifica).
- Sem `!` para forçar opcionais e sem `try!`: o lint bloqueia.
- O `AERESBarCore` não importa AppKit nem SwiftUI. Texto exibido na tela é gerado no Core (`UsagePresentation`, `BarPresenter`) para ser testável.
- Todo acesso externo (rede, processos, arquivos de credencial, relógio) passa por um protocolo injetável. Os testes nunca tocam a rede nem o Chaves.
- Textos da interface em português do Brasil; identificadores e comentários em inglês.

## Novo provedor

1. Crie `Sources/AERESBarCore/Providers/<Nome>/`. Se o serviço é lido por HTTP com uma chave, descreva-o como um `KeyedService` (regiões, requisição, parser, erro no corpo, credencial local) e registre um `KeyedUsageProvider`; se só um CLI oficial lê o uso, descreva um `CommandService` para o `CommandUsageProvider`. Nos outros casos, escreva um `actor` que implemente `UsageProvider` (`snapshot(previous:reason:)`) e use `FetchPolicy` e `FetchState`, que cuidam do reaproveitamento, da leitura manual e das pausas pedidas com HTTP 429.
2. Coloque os parsers em tipos puros, testados com fixtures anonimizadas em `Tests/AERESBarCoreTests/Fixtures`.
3. Se o serviço não deixa um login no Mac, adicione uma conta em `SecretAccount` e leia a chave pelo `SecretStore` injetado; o menu **Chaves de API** e o `--set-key` passam a oferecê-la sozinhos. Inclua a conta no `scripts/uninstall.sh` (um teste confere).
4. Adicione o caso em `ProviderID`, a marca oficial em `BrandMark`, as cores em `BrandPalette` e um snapshot de exemplo em `DemoData`.
5. Registre o provedor em `LiveEnvironment` e atualize o README, o `docs/ARCHITECTURE.md` e o CHANGELOG.

## Dados sensíveis

Fixtures, logs, prints e issues nunca devem conter tokens, e-mails ou IDs de conta reais. Os parsers só registram no log o *tipo* de falha (`ProviderIssue.Kind`), nunca respostas ou credenciais.
