# Alfaeq Yemen — docs-cockpit + pro-workflow Integration

## docs-cockpit
Use docs-cockpit as an **engineering cockpit**, not as the application's runtime dashboard.

Adopt:
- schema-validated project/module/spec metadata
- deterministic documentation rendering
- machine-readable project state
- drift detection and evidence-linked documentation
- Kanban/sprint/KPI views for engineering work

Do not add its Python runtime to Flutter production. If enabled later, run it as a development/CI documentation tool.

## pro-workflow
Use pro-workflow as an **agent engineering workflow reference**.

Adopt:
- research -> plan -> implement -> validate -> review -> commit
- persistent correction/learning capture for engineering agents
- deterministic secret/git guards
- mandatory lint/typecheck/test gates
- explicit approval before autonomous plan expansion
- wrap-up and handoff evidence
- isolated worktrees for parallel engineering tasks

Do not place its SQLite agent memory inside Supabase business data and do not make it a production dependency.

## Alfaeq mapping

| Capability | Alfaeq implementation |
|---|---|
| Project state | Git + docs + CI evidence |
| Business state | Supabase/Postgres |
| Agent memory | Development-only agent tooling |
| Quality gates | GitHub Actions |
| Security | security-audit-gate + RLS/function review |
| Event state | automation_events |
| Automation | automation-worker -> n8n |
| Documentation | docs/ with explicit evidence links |

The two repositories therefore improve the engineering/control plane while leaving the customer-facing production plane unchanged.
