# Alfaeq Build Platform

This directory defines the production blueprint for the next Alfaeq platform layer.

The platform is the governed engineering control plane that turns a request into
a specification, isolated execution, verification evidence, and a deployable artifact.

## Execution contract

1. A user request becomes an ai_tasks record.
2. An eligible agent is claimed transactionally.
3. The executor works against an isolated branch/workspace.
4. Decisions are routed through Jev where structured decisions are useful.
5. Code changes are verified by GitHub Actions.
6. Browser work is independently verified before mutation.
7. Production changes reach main only through reviewed pull requests.
8. Supabase remains the production source of truth.

## Adapter policy

Repositories listed in blueprint.yaml are capability sources, not code to copy
blindly. We reuse interfaces, patterns, and narrowly scoped components while
preserving Alfaeq's Supabase/RLS/event-bus architecture.

## Initial build domains

- App Factory: Flutter/Web/Android project generation.
- Service Factory: Edge Functions and worker-service generation.
- Site Factory: website generation/import and asset normalization.
- Agent Factory: specification, execution, testing, and repair loops.
- Browser Automation: dynamic action selection with independent outcome checks.
- Knowledge/Research: web discovery and structured extraction.
- Governance: security, idempotency, audit, budgets, and PR gates.
