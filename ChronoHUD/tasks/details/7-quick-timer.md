# 7-quick-timer

- Number: 7
- Slug: quick-timer

## Notes

## Estado em 2026-07-21

Implementação e validação automatizada concluídas; tarefa mantida como `claimed`
até o checklist manual ser executado e registrado pelo usuário.

## Decisão de produto — simplificação dos atalhos (2026-07-21)

Esta decisão substitui deliberadamente a exigência visual do contrato original
que previa uma área/aba de Atalhos com três pickers, inclusive o terceiro picker
do Timer rápido.

Para o MVP:

- remover a interface de personalização de atalhos das Preferências;
- manter `⇧⌘Space` fixo para abrir o Timer rápido;
- manter `Timer rápido…` sempre disponível na barra de menus como alternativa;
- manter os demais atalhos existentes fixos, sem controles de personalização;
- preservar internamente o backend transacional, tokens, tratamento de erros e
  testes de hotkeys já implementados;
- em conflito real, não alterar silenciosamente a combinação nem criar nova UI
  complexa: informar de forma discreta que o atalho está indisponível e manter o
  acesso pelo menu;
- adiar qualquer personalização para uma futura seção `Avançado`.

Escopo da substituição: somente a UI de configuração descrita nas seções 9 e 10
do checklist original. Parser, painel, motor, persistência, comportamento das
teclas, acessibilidade, menu, registro Carbon e critérios técnicos continuam
válidos.

### Evidências automatizadas

- `AGENT_NAME=CODEX make agent-verify`: passou (build estrito + 46 testes).
- SwiftLint: verificação opcional ignorada porque o executável não está instalado.
- `git diff --check`: passou.
- `plutil` do projeto e Info.plist: passou.
- `jq empty ChronoHUD/Resources/Localizable.xcstrings`: passou.
- Archive Release: `build/archive/CODEX/ChronoHUD.xcarchive` passou.
- Produto do archive: assinatura válida, `LSUIElement = true`, binário universal
  `arm64`/`x86_64`.
- Entitlements do archive: App Sandbox e acesso a arquivo escolhido pelo usuário;
  nenhuma permissão de Acessibilidade.
- Busca por `TODO`/`FIXME` nos arquivos alterados: nenhum fallback pendente.

### Cobertura adicionada

- Parser e classificação de todos os formatos obrigatórios.
- Fluxos do modelo do painel, Return/keypad Enter/Option/Escape e repeat.
- Motor, substituição atômica, snapshot único, override de repetição e JSON legado.
- Hotkeys: inicialização, despacho, rollback, persistência, no-op, duplicidade e
  falhas separadas de handler/registro.
- Falha suplementar de notificação não interrompe o Timer rápido nem toca som.

### Checklist manual pendente

- [ ] Abertura pelo menu e pelo hotkey `⇧⌘Space`.
- [ ] Return, keypad Enter e `⌥Return` no painel real.
- [ ] Teclado ABNT2 e fontes de entrada pt-BR/inglês.
- [ ] Reaberturas e foco renovado.
- [ ] VoiceOver.
- [ ] Fullscreen, Spaces e Mission Control.
- [ ] Dois monitores e captura de posicionamento antes do deferimento do menu.
- [ ] `⌘Tab`, clique externo e restauração sem roubar foco.
- [ ] Reduzir Movimento, Reduzir Transparência e Aumentar Contraste.
- [ ] Conflito real de hotkeys com outro aplicativo.
- [ ] Confirmar que duração e repetição globais permanecem inalteradas.

### Continuação em 2026-07-21 16:02 BRT

- Novo archive Release gerado em `build/archive/CODEX/ChronoHUD.xcarchive` com
  `GCC_TREAT_WARNINGS_AS_ERRORS=YES`, `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`,
  `SWIFT_STRICT_CONCURRENCY=complete` e
  `OTHER_SWIFT_FLAGS=$(inherited) -Xfrontend -disable-sandbox`.
- O archive concluiu com sucesso; `lipo -archs` confirmou `x86_64 arm64`.
- Foi aberto exclusivamente o produto deste archive. O menu extra exibiu
  `Timer rápido…` e o aviso secundário de conflito, mantendo o acesso pelo menu.
- Ao abrir pelo menu, o painel foi apresentado e o System Events observou dois
  windows, com o campo de duração como elemento focado. Não houve clique no
  campo para forçar foco.
- A validação manual de Return, keypad Enter, `⌥Return`, Escape e reaberturas
  não foi concluída: a permissão de automação do System Events para o teste de
  teclas foi recusada. Nenhuma alteração de código foi feita e a tarefa segue
  `claimed`; não executar `done 7` sem esses resultados ou orientação explícita.

## Handoff para a próxima conversa

1. Ler este arquivo. Em caso de conflito com o contrato/checklist original,
   aplicar primeiro a decisão de produto sobre atalhos registrada acima.
2. Preservar todas as alterações existentes; não recriar nem descartar o worktree.
3. Implementar somente a simplificação visual dos atalhos: remover a UI de
   personalização, manter `⇧⌘Space` fixo e preservar backend/testes.
4. Como essa mudança altera código, executar uma única verificação automatizada
   depois que a edição estiver pronta. Não repetir build, testes, archive,
   assinatura ou entitlements antes disso.
5. Gerar então um novo archive e executar o app com:

   ```bash
   open "build/archive/CODEX/ChronoHUD.xcarchive/Products/Applications/ChronoHUD.app"
   ```

6. Realizar e registrar cada item do checklist manual acima. Se `onKeyPress` não
   entregar Return, keypad Enter, Option+Return ou Escape no `NSPanel` real,
   substituir integralmente a estratégia pelo monitor local descrito no contrato;
   nunca manter as duas estratégias juntas.
7. Se os testes manuais exigirem nova correção, repetir uma única vez ao final:

   ```bash
   AGENT_NAME=CODEX make agent-verify
   ```

   e gerar novamente o archive Release.
8. Somente depois de todos os itens manuais passarem, concluir com:

   ```bash
   AGENT_NAME=CODEX scripts/task.sh done 7 \
     --note "Finished + build/test/archive/manual validation status"
   ```

Não há commit ou stage criado. O worktree contém exclusivamente a implementação
em andamento da tarefa 7 e seu registro em `tasks/`.
