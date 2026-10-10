# Alfaeq Order / Inventory / Merchant Event Contracts

## Source of truth
Supabase PostgreSQL is authoritative for orders, products/inventory, stores/merchants, and the durable `automation_events` stream. n8n is an automation consumer/orchestrator, not a business-data source of truth. The production database already has a private outbox helper (`private.enqueue_automation_event`) used by order/store triggers.

## Events

| Event | Aggregate | Producer | Purpose |
|---|---|---|---|
| `order.created` | order | `orders` INSERT trigger | Starts trusted order processing and downstream automation. |
| `order.updated` | order | existing `private.trg_enqueue_order_event` | Propagates order changes. |
| `inventory.reserved` | inventory | `inventory_movements` INSERT | Records successful sale reservation after the atomic inventory operation. |
| `inventory.released` | inventory | `inventory_movements` INSERT | Records reservation/release movements. |
| `inventory.adjusted` | inventory | `inventory_movements` INSERT | Records other inventory ledger movements. |
| `store.created` | store | existing `private.trg_enqueue_store_event` | Starts merchant/store onboarding automation. |
| `store.updated` | store | existing `private.trg_enqueue_store_event` | Propagates store changes. |

## Reliability boundaries

1. Business mutations happen first in PostgreSQL transactions.
2. Event producers run as database triggers after the business row mutation.
3. `automation_events` is durable and consumed by `automation-worker`.
4. `automation-worker` retries failed delivery with backoff and stops after its configured attempt limit.
5. `automation_event_inbox.event_id` is unique for idempotent external ingestion.
6. A claim that is left in `processing` (worker timeout, cold-start kill, redeploy) is recovered: `reap_stale_automation_inbox()` returns stale claims to `received`, and the scheduled `private.automation_inbox_drain_internal()` drain re-invokes the worker after retry backoff. This mirrors the legacy `claim_automation_events()` self-healing path so no accepted event is silently dropped.
7. Inventory reservation is itself idempotent through the unique `sale_reservation` movement constraint and row locking.
8. If inventory reservation fails, the PostgreSQL transaction rolls back; no `inventory.reserved` event is emitted for the failed reservation.
9. No client is granted execution of privileged inventory functions or the event producer function.

## Verification required

The integration is not considered complete until CI provides fresh evidence for:
- `flutter analyze`
- `flutter test`
- `flutter build web --release`
- `flutter build apk --debug`
- migration/static inspection confirms trigger coverage and restricted function execution.

