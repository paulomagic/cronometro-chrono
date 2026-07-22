# Tasks

## Task IDs

1. audit-native-implementation
   Id: 1-audit-native-implementation
   Scope: Review the complete native CHRONO HUD implementation using the project-local Swift, SwiftUI, SwiftData, lint, Xcode, and documentation tooling.
   Files: ChronoHUD/,ChronoHUDTests/,Resources/,AppStore/,project.pbxproj,Makefile,scripts/
   Note: Audit completed. Baseline Debug arm64 XCTest passed 7/7 in /tmp. Strict-concurrency build failed on AppDelegate.model. make agent-verify also exposed unescaped-space handling in xcbuild cache flags. No implementation files changed.
   Detail: tasks/details/1-audit-native-implementation.md
   Claimed by: CODEX
   Claimed at: 2026-07-19T01:00:49Z
   Done by: CODEX
   Done at: 2026-07-19T01:10:08Z

2. fix-audit-findings
   Id: 2-fix-audit-findings
   Scope: Corrigir itens 1-9 da auditoria nativa; validar testes, concorrencia estrita e agent-verify; documentar pendencias externas App Store
   Files: ChronoHUD/DomainModels.swift,ChronoHUD/TimerEngine.swift,ChronoHUD/Views.swift,ChronoHUD/ChronoHUDApp.swift,ChronoHUD/AppServices.swift,ChronoHUDTests,Makefile,scripts/xcbuild.sh,.swiftlint.yml
   Note: Finished audit items 1-9. Strict build passed; 13/13 XCTest passed via AGENT_NAME=CODEX make agent-verify; SwiftLint config/optional target added, tool not installed. App Store URLs/contact/screenshots/archive remain user-dependent.
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
   Note: Implemented two-way Full/Essential HUD switching, dedicated 352x92 essential controls/status layout, persistent preference, localized accessibility/help, and top-left-preserving panel resize. Strict build passed; 15 XCTest cases passed outside sandbox. Manual UI validation stopped per user request; no git add/commit/push.
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
   Scope: Review all uncommitted changes, run relevant validation, commit and push if correct
   Files: ChronoHUD ChronoHUDTests Makefile scripts .swiftlint.yml agents tasks
   Note: Reviewed all uncommitted changes; fixed notification replacement race and added regression coverage; strict warning-as-error build passed; 17/17 XCTest passed; SwiftLint optional tool unavailable; diff and string catalog validation passed
   Detail: tasks/details/6-review-uncommitted.md
   Claimed by: CODEX
   Claimed at: 2026-07-20T15:32:37Z
   Done by: CODEX
   Done at: 2026-07-20T15:40:01Z

7. quick-timer
   Id: 7-quick-timer
   Scope: Implementar somente o Timer rápido do MVP
   Files: ChronoHUD/*.swift ChronoHUDTests/*.swift ChronoHUD/Resources/Localizable.xcstrings ChronoHUD.xcodeproj/project.pbxproj
   Note: Completed Quick Timer implementation, mode selector dynamic accent theme, button hit testing area fix, and synchronous opacity pipeline.
   Detail: tasks/details/7-quick-timer.md
   Claimed by: CODEX
   Claimed at: 2026-07-21T15:38:45Z
   Done by: CODEX
   Done at: 2026-07-21T21:07:00Z

