# Alfaeq Compost-Style SDLC

Date: 2026-09-29

## Purpose

Adopt useful engineering workflow patterns from claude-plugins/compost without adding Claude Code plugins to the Flutter production runtime.

## Required unit of work

1. Spec — define the problem and affected boundary.
2. Acceptance criteria — define observable Given/When/Then outcomes.
3. Plan — identify the smallest safe implementation.
4. Build — make one coherent, reviewable change.
5. Verify — run meaningful tests plus repository CI gates.
6. Review — inspect correctness, security, regressions and unnecessary complexity.
7. Evidence — retain CI/build/test evidence before calling the change complete.

## Alfaeq constraints

- Supabase/Postgres remains authoritative for orders, inventory, payments, wallets and settlements.
- Flutter must not contain Supabase service-role credentials.
- Production inventory mutation remains behind transactional server-side domain functions.
- AI, browser, RAG and n8n workers are downstream orchestrators and cannot become the source of truth.
- No fake production financial transactions for testing.
- Event processing preserves eventId, eventType, occurredAt and idempotency.

## Evidence chain

Spec -> Acceptance -> Diff -> Tests -> CI -> Review -> Evidence

The engineering-gates workflow enforces the machine-checkable subset. Existing Flutter CI, build, security-audit and browser-QA workflows remain authoritative for their domains.

## Source

Reference repository: safwt771754091s-crypto/claude-plugins
