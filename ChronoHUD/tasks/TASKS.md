# Tasks

## Task IDs

1. audit-native-implementation
   Id: 1-audit-native-implementation
   Scope: Revisar a implementação nativa completa do CHRONO HUD utilizando ferramentas locais do projeto em Swift, SwiftUI, SwiftData, lint, Xcode e documentação.
   Files: ChronoHUD/,ChronoHUDTests/,Resources/,AppStore/,project.pbxproj,Makefile,scripts/
   Note: Auditoria concluída. XCTest Debug arm64 baseline passou 7/7 em /tmp. Build de concorrência estrita falhou em AppDelegate.model. make agent-verify também expôs o tratamento de espaços não escapados em flags de cache do xcbuild. Nenhum arquivo de implementação foi alterado.
   Detail: tasks/details/1-audit-native-implementation.md
   Claimed by: CODEX
   Claimed at: 2026-07-19T01:00:49Z
   Done by: CODEX
   Done at: 2026-07-19T01:10:08Z

2. fix-audit-findings
   Id: 2-fix-audit-findings
   Scope: Corrigir itens 1-9 da auditoria nativa; validar testes, concorrência estrita e agent-verify; documentar pendências externas App Store
   Files: ChronoHUD/DomainModels.swift,ChronoHUD/TimerEngine.swift,ChronoHUD/Views.swift,ChronoHUD/ChronoHUDApp.swift,ChronoHUD/AppServices.swift,ChronoHUDTests,Makefile,scripts/xcbuild.sh,.swiftlint.yml
   Note: Concluídos os itens 1-9 da auditoria. Build estrito passou; 13/13 XCTest passaram via AGENT_NAME=CODEX make agent-verify; target opcional/config de SwiftLint adicionado, ferramenta não instalada. URLs da App Store/contato/capturas de tela/archive permanecem dependentes do usuário.
   Detail: tasks/details/2-fix-audit-findings.md
   Claimed by: CODEX
   Claimed at: 2026-07-19T01:15:30Z
   Done by: CODEX
   Done at: 2026-07-19T01:28:19Z

3. fix-opacity-presets
   Id: 3-fix-opacity-presets
   Scope: Corrigir atraso e seleção incorreta dos presets de transparência no HUD
   Files: ChronoHUD/Views.swift,ChronoHUDTests/TimerEngineTests.swift
   Note: Corrigida observação direta de SettingsStore no OverlayContentView e aplicação síncrona do valor publicado no NSPanel; presets 100/80/60/40/20 e slider 55% validados manualmente; AGENT_NAME=CODEX make agent-verify passou com 14 testes; SwiftLint opcional indisponível.
   Detail: tasks/details/3-fix-opacity-presets.md
   Claimed by: CODEX
   Claimed at: 2026-07-19T01:34:33Z
   Done by: CODEX
   Done at: 2026-07-19T01:43:20Z

4. minimal-hud-layout
   Id: 4-minimal-hud-layout
   Scope: Evoluir o HUD compacto para um layout essencial funcional e alternável pelo painel
   Files: ChronoHUD/Views.swift,ChronoHUD/OverlayPanelController.swift,ChronoHUD/DomainModels.swift,ChronoHUD/Resources/Localizable.xcstrings,ChronoHUDTests/TimerEngineTests.swift
   Note: Implementada alternância bidirecional Completo/Essencial do HUD, layout dedicado de 352x92 para controles/status essenciais, preferência persistente, acessibilidade/ajuda localizadas e redimensionamento de painel preservando o canto superior esquerdo. Build estrito passou; 15 casos de teste XCTest passaram fora do sandbox. Validação manual de UI pausada por solicitação do usuário; sem git add/commit/push.
   Detail: tasks/details/4-minimal-hud-layout.md
   Claimed by: CODEX
   Claimed at: 2026-07-19T02:08:12Z
   Done by: CODEX
   Done at: 2026-07-19T02:20:40Z

5. fix-first-click-expanded-hud
   Id: 5-fix-first-click-expanded-hud
   Scope: Diagnosticar e corrigir controles do layout Completo que exigem segundo clique, sem regressão no layout Essencial ou arraste do painel
   Files: ChronoHUD/OverlayPanelController.swift,ChronoHUD/Views.swift,ChronoHUDTests/TimerEngineTests.swift
   Note: Corrigida a perda do primeiro mouse event com FirstMouseHostingView.acceptsFirstMouse; adicionado teste de regressão; incluído botão xmark para sair no cabeçalho completo e áreas 20x20 para layout/pin/sair. AGENT_NAME=CODEX make agent-verify passou com build estrito e 16/16 XCTest; SwiftLint opcional ausente. Validação manual confirmou presets, iniciar/pausar, modos, pin, Completo↔Essencial, arraste, Exportar/Limpar e confirmação de saída no primeiro clique.
   Detail: tasks/details/5-fix-first-click-expanded-hud.md
   Claimed by: CODEX
   Claimed at: 2026-07-19T02:32:24Z
   Done by: CODEX
   Done at: 2026-07-19T02:47:05Z

6. review-uncommitted
   Id: 6-review-uncommitted
   Scope: Revisar todas as alterações não comitadas, executar validação relevante, comitar e enviar (push) se correto
   Files: ChronoHUD ChronoHUDTests Makefile scripts .swiftlint.yml agents tasks
   Note: Revisadas todas as alterações não comitadas; corrigida condição de corrida na substituição de notificações e adicionada cobertura de regressão; build estrito com warnings-como-erros passou; 17/17 XCTest passaram; ferramenta opcional SwiftLint indisponível; validação de diff e catálogo de strings passou.
   Detail: tasks/details/6-review-uncommitted.md
   Claimed by: CODEX
   Claimed at: 2026-07-20T15:32:37Z
   Done by: CODEX
   Done at: 2026-07-20T15:40:01Z

7. quick-timer
   Id: 7-quick-timer
   Scope: Implementar somente o Timer rápido do MVP
   Files: ChronoHUD/*.swift ChronoHUDTests/*.swift ChronoHUD/Resources/Localizable.xcstrings ChronoHUD.xcodeproj/project.pbxproj
   Note: Concluídos a implementação do Timer rápido, tema de destaque dinâmico no seletor de modo, correção de área de clique do botão e pipeline síncrono de opacidade.
   Detail: tasks/details/7-quick-timer.md
   Claimed by: CODEX
   Claimed at: 2026-07-21T15:38:45Z
   Done by: CODEX
   Done at: 2026-07-21T21:07:00Z
