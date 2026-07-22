# Notas para Revisão do Aplicativo (App Review)

O CHRONO HUD é um utilitário nativo para a barra de menus do macOS com um painel flutuante de cronômetro. Não requer conta, conexão de rede, assinatura, compra nem credenciais de demonstração.

## Fluxo de revisão sugerido

1. Inicie o aplicativo e conclua a introdução (onboarding) curta.
2. O HUD flutuante aparece automaticamente; o ícone de cronômetro na barra de menus fornece os demais controles.
3. Teste os modos Cronômetro, Contagem Regressiva e Pomodoro no HUD.
4. Expanda o log de eventos para inspecionar os eventos do cronômetro ou exportá-los em TXT.
5. Abra o Histórico pela barra de menus para inspecionar sessões concluídas e exportar em CSV/JSON.
6. Abra as Configurações para testar o modo compacto, tema, cor de destaque, transparência, comportamento de conclusão e durações.
7. Os atalhos globais padrão são Command-Shift-C para exibir/ocultar o HUD e Command-Shift-T para alternar o modo que ignora cliques.

O aplicativo utiliza notificações locais apenas para conclusão da Contagem Regressiva e Pomodoro. A permissão de notificação é solicitada na primeira vez que uma sessão temporizada precisar dela.

O App Sandbox está ativado. O acesso de leitura/escrita a arquivos selecionados pelo usuário é usado apenas para exportações através do painel de salvamento padrão do macOS. Todos os dados do cronômetro e preferências são armazenados localmente. O aplicativo não coleta dados e não realiza rastreamento.

`ITSAppUsesNonExemptEncryption` está definido como `false`; o aplicativo não implementa nem inclui criptografia não isenta.
