# Alfaeq Engineering Skill Gates

This project uses the `claude-skills` repository as a reference library for engineering-agent workflows. Skills are not copied wholesale into the Flutter runtime.

## Required gates for production changes

1. **Architecture review** — identify the authoritative data owner and the affected service boundary.
2. **Security review** — check authentication, authorization, RLS, secrets, SECURITY DEFINER exposure, input validation and webhook authentication.
3. **Database review** — verify migrations, indexes, constraints, idempotency and transactional behavior.
4. **Test review** — add or update the smallest meaningful automated test; do not create fake production transactions.
5. **CI gate** — require Flutter analyze/test/build evidence before treating a code change as production-ready.
6. **Event contract review** — eventId/eventType/occurredAt must be explicit; duplicate delivery must be idempotent.
7. **Operational review** — AI, browser automation, RAG and external integrations may enrich or orchestrate work but cannot become the source of truth for orders, inventory, payments, wallets or settlements.

## Selected skill families from claude-skills

- adversarial review
- AI security
- cloud security
- code review
- CI/CD engineering
- database architecture
- Playwright/browser testing
- reliability/SLO engineering
- agent design

## Integration rule

Use these as engineering playbooks and review gates. Do not add the full skill repository, its Python tools, or agent plugins to the mobile/web production bundle.

Source repository: https://github.com/safwt771754091s-crypto/claude-skills
