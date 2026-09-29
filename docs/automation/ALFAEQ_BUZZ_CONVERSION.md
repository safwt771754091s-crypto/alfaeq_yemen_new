# Alfaeq — Buzz Automation Conversion

Buzz concepts are being converted into Alfaeq-native infrastructure, not copied as a second backend.

## Production flow

Flutter -> automation-event-gateway -> accept_automation_event -> automation_event_inbox -> automation-worker -> n8n

AI events continue through ai-event-worker -> ai_agents -> ai_tasks -> ai_activity_log.

## Adopted concepts
- Typed event triggers and dotted event names.
- Durable idempotent event inbox.
- Workflow orchestration separated from business data.
- Agent roles, budgets and activity.
- Human approval for sensitive actions.
- Tool audit logs.
- External webhooks as automation adapters.

## Event contract
- source
- version
- eventId
- eventType
- occurredAt
- data

eventId is the idempotency key. Replaying the same event must return duplicate=true and must not create another inbox row.

## Initial event vocabulary
order.created, order.confirmed, order.cancelled, inventory.changed, inventory.reserved, merchant.updated, store.updated, product.created, product.updated, promotion.published, delivery.assigned, delivery.completed, payment.authorized, payment.settled, wallet.ledger_posted, notification.requested, ai.task_created.

## Security boundary
Flutter never receives a service-role key. The protected inbox remains inaccessible to anon/authenticated roles. The gateway requires a valid Supabase session and calls the restricted RPC server-side.

## Deliberately excluded
- Buzz/Nostr as primary identity or database.
- Buzz Rust relay runtime.
- A second queue competing with automation_events.
- Direct Flutter writes to protected automation tables.
- Experimental agent permissions without an Alfaeq policy.

Supabase remains the operational source of truth and n8n remains the external automation orchestrator.