# Alfaeq Yemen — Supabase Load Optimization

Date: 2026-09-29

## Objective
Keep Supabase as the source of truth for transactional state while moving non-transactional orchestration, reporting, AI work, and external integrations to dedicated workers/services.

## Responsibility boundaries

| Work | Primary layer | Supabase role |
|---|---|---|
| Auth, users, roles/RLS | Supabase | Source of truth |
| Products, inventory, orders | Supabase/Postgres | Atomic transactional state |
| Payments, wallets, settlements | Supabase/Postgres | Ledger and final state |
| Durable event inbox/idempotency | Supabase/Postgres | Durable ingress/state |
| Event delivery/retry | automation-worker | Queue state + audit only |
| n8n integrations | n8n | Receives events, executes external workflows |
| AI decisions/tasks | AI workers + JEV/GAIA | Task/decision audit state |
| WhatsApp / external notifications | n8n or dedicated workers | Delivery status/audit |
| Google Sheets | n8n/reporting workers | Import/export/reporting only |
| Browser/research automation | isolated workers | No transactional authority |
| Code/CI/docs/QA | GitHub Actions + repositories | No production business state |

## Rules

1. Never move inventory reservation, order totals, payment state, wallet balances, or settlement state into Google Sheets or AI memory.
2. n8n must remain an orchestrator/integration layer, not the source of truth.
3. AI agents may recommend or execute only according to explicit capability gates; irreversible financial/stock mutations remain server-side.
4. Google Sheets is an operational/reporting surface. Imports must be validated and audited before affecting production catalog data.
5. Prefer one durable event ingress path. Legacy event queues should be drained and retired only after production evidence confirms the new inbox path is complete.
6. Every load-reduction change must preserve idempotency, retry behavior, and auditability.
7. No production test orders or artificial financial transactions are created for load testing.

## Current optimization findings

- automation-worker currently supports both the durable automation_event_inbox path and a legacy automation_events queue. This is useful for compatibility, but creates duplicate queue logic and should be consolidated after migration evidence is collected.
- ai-event-worker already keeps AI work in task/audit tables and uses an event idempotency lookup; this is the correct direction for keeping AI execution outside transactional business logic.
- automation-event-gateway validates authenticated event submissions and persists them through the database event acceptance function; this remains the controlled ingress path.
- External integrations should be triggered from the durable event pipeline rather than directly from Flutter.
- Current Supabase security advisors report two exposed SECURITY DEFINER chat RPCs and leaked-password protection disabled. These are separate security hardening tasks and should be addressed before expanding public automation surface.

## Target flow

Flutter -> Supabase transactional state -> durable automation event -> worker -> n8n / AI / external services -> result/audit back to Supabase.

Google Sheets receives/reporting data through n8n and never becomes the transactional database.

## Success criteria

- Lower Edge Function/API work for non-transactional tasks.
- Fewer duplicate event-processing paths.
- No loss of transactional guarantees.
- No secrets in Flutter or repositories.
- Every externally triggered action remains traceable to an event ID.
- CI/build/QA remain green after each implementation change.
