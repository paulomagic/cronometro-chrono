# Regras do fluxo de trabalho de agentes

- Use `scripts/task.sh` como ponto de entrada único de tarefas.
- Use `AGENT_NAME` ao reivindicar e concluir trabalhos.
- Mantenha o backlog de tarefas em `tasks/TASKS.md`.
- Coloque notas detalhadas das tarefas em `tasks/details/<id>.md`.

Comandos do fluxo de trabalho de tarefas:
- `scripts/task.sh plan <slug> --scope "..." --files "..." --note "..."`
- `AGENT_NAME=CODEX scripts/task.sh claim <número|id> --note "Iniciando trabalho"`
- `AGENT_NAME=CODEX scripts/task.sh done <número|id> --note "Concluído + status de build/test"`
- `scripts/task.sh summary --last-24h`
