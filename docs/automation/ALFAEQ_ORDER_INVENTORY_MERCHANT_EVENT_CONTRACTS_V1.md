# Alfaeq Order / Inventory / Merchant Event Contracts

## Source of truth
Supabase PostgreSQL is authoritative for orders, products/inventory, stores/merchants, and the durable `automation_events` stream. n8n is an automation consumer/orchestrator, not a business-data source of truth.

## Events

| Event | Aggregate | Producer | Purpose |
|---|---|---|---|
| `order.created` | order | `orders` INSERT trigger | Starts trusted order processing and downstream automation. |
| `order.status_changed` | order | `orders` UPDATE trigger | Propagates merchant/customer/delivery state changes. |
| `inventory.reserved` | inventory | `inventory_movements` INSERT | Records successful sale reservation after the atomic inventory operation. |
| `inventory.released` | inventory | `inventory_movements` INSERT | Records reservation/release movements. |
| `inventory.adjusted` | inventory | `inventory_movements` INSERT | Records other inventory ledger movements. |
| `merchant.store.created` | merchant | `stores` INSERT trigger | Starts merchant/store onboarding automation. |
| `merchant.store.updated` | merchant | `stores` UPDATE trigger | Propagates material merchant/store changes. |

## Reliability boundaries

1. Business mutations happen first in PostgreSQL transactions.
2. Event producers run as database triggers after the business row mutation.
3. `automation_events` is durable and consumed by `automation-worker`.
4. `automation-worker` retries failed delivery with backoff and stops after its configured attempt limit.
5. `automation_event_inbox.event_id` is unique for idempotent external ingestion.
6. Inventory reservation is itself idempotent through the unique `sale_reservation` movement constraint and row locking.
7. If inventory reservation fails, the PostgreSQL transaction rolls back; no `inventory.reserved` event is emitted for the failed reservation.
8. No client is granted execution of privileged inventory functions or the event producer function.

## Verification required

The integration is not considered complete until CI provides fresh evidence for:
- `flutter analyze`
- `flutter test`
- `flutter build web --release`
- `flutter build apk --debug`
- migration/static inspection confirms trigger coverage and restricted function execution.

