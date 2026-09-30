# Alfaeq Unified Automation Contract

## Ownership of responsibilities

- **Alfaeq Yemen app:** creates/updates business state only.
- **Supabase:** system of record for business state and the canonical automation event inbox.
- **automation_event_inbox:** single durable ingress for new automation events; unique `event_id` provides idempotency.
- **automation-worker:** claims inbox events, retries failures, and delivers the canonical event contract to n8n.
- **n8n Cloud:** orchestration and external integrations; it must not become the source of truth for orders, inventory, payments, wallets, or settlements.
- **GitHub:** source of code, migrations, workflow contracts, CI, review, and release evidence.

## Canonical event

Every event delivered to n8n uses:

```json
{
  "source": "supabase",
  "version": 1,
  "eventId": "stable-or-generated-id",
  "eventType": "order.created",
  "occurredAt": "2026-09-30T19:00:00Z",
  "data": {
    "aggregateType": "order",
    "aggregateId": "..."
  },
  "payload": {}
}
```

## Event families

The database event bus covers the transactional domains already present in Supabase:

- identity/account: `account_member.*`
- catalog: `section.*`, `store.*`, `product.*`, `promotion.*`
- commerce: `order.*`, `inventory.*`, `payment.*`, `invoice.*`, `settlement.*`
- delivery: `driver.*`, `delivery_event.*`
- wallet: `wallet_operation.*`, `wallet_transaction.*`, `wallet_ledger.*`
- communication: `chat_thread.*`, `chat_member.*`, `chat_message.created`, `notification.*`
- platform/content: `site_update.*`, `platform_account.*`, `review.*`

## Non-negotiable rules

1. Business transactions stay in Supabase.
2. Inventory changes stay in inventory/ledger paths; n8n cannot directly mutate stock.
3. Wallet/ledger changes stay transactional and idempotent in Supabase.
4. n8n may orchestrate external effects such as Google Sheets, WhatsApp, media processing, email, and AI jobs.
5. Secrets stay in Supabase server configuration or n8n credentials/variables, never Flutter or Git history.
6. New producers should emit to `automation_event_inbox`; the legacy `automation_events` table is retained only for controlled backlog compatibility.
7. The old direct `automation_events` worker trigger is disabled so new events cannot fork into two delivery paths.

## Production cutover

- Keep the existing n8n Cloud workflow as the live endpoint.
- Update the live workflow to match this contract before enabling new external handlers.
- Do not replay the legacy backlog automatically.
- Verify with `test.ping`, then a real product/store/order event.
- After cutover, GitHub's workflow JSON is the versioned contract and n8n Cloud is the live execution surface.
