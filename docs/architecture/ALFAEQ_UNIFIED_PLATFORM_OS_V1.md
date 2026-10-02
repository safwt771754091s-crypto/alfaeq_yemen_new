# Alfaeq Yemen — Unified Platform Operating System v1

## Architecture decision

The platform is one product with three runtime layers:

1. **Flutter** — customer/merchant/driver/owner UX and authenticated user actions.
2. **Supabase** — source of truth: Auth, PostgreSQL, RLS, Realtime, Storage, RPCs and Edge Functions.
3. **n8n Cloud** — external orchestration only. It consumes canonical events and runs integrations; it does not own orders, inventory, payments, wallets or settlements.

### Canonical flow

```
Flutter
  -> Supabase Auth/RLS/RPC
  -> PostgreSQL transaction
  -> automation_event_inbox
  -> automation-worker
  -> n8n Cloud
  -> external side effects
```

AI has two paths:

- **Interactive Alfaeq AI:** Flutter -> authenticated `ai-gateway` -> configured model provider.
- **Autonomous operations:** event -> `ai-event-worker` -> `ai_tasks` -> `ai-executor-dispatcher` -> OpenHands/agent runtime.

Chat has two paths:

- **Human support chat:** `chat_threads`, `chat_members`, `chat_messages` + Supabase Realtime/RLS.
- **AI assistant:** `AlfaeqAiService` -> `ai-gateway`, with permission checks and confirmation before mutating operations.

## Commercial domains

The existing production schema already contains the main domains:

- users/roles
- sections/catalog
- stores/merchants
- products
- carts
- orders/order_items
- inventory
- drivers/delivery
- payments
- wallets/ledger/settlements
- notifications
- media
- automation
- chat
- AI control plane

The event bus covers the domain events without moving business state into n8n.

## Repository capabilities adopted

### buzz
Adopted as architecture patterns only: typed event envelopes, one durable event stream, humans and agents as first-class actors, searchable auditability, workflow approval gates, and agent actions scoped by identity. Buzz/Nostr is **not** introduced as a second database or identity system.

### Jev
Adopted for machine decisions that benefit from typed Choice/Score/Noul outputs, confidence routing and guardrail classification. Generative models remain responsible for prose and open-ended answers. Business side effects stay in code/RPCs.

### Learn Harness Engineering
Adopted as operating discipline: repository instructions, explicit state, verification gates, maker/checker loops, graph routing, durable external state, and evidence before claiming completion.

### Agent Reach / Scrapling
Reserved for controlled web research/catalog ingestion. Scraping output must enter an import pipeline and never directly mutate production inventory or orders.

### OpenSandbox
Reserved as an isolated execution boundary for untrusted agent/tool work. It is not the production database and is not a replacement for Supabase RLS.

### VoiceStudio
Reserved as a media/voice capability behind a provider adapter; it does not become the core chat transport.

### Website-downloader
Reserved for an explicit website-import capability with quotas/timeouts and sandboxing; it must not run arbitrary production-shell commands.

### Naive-N0.5-Flash
Treated as an optional model provider. Its published model size/GPU requirements make it unsuitable as an implicit Supabase runtime dependency; use a provider adapter when infrastructure is available.

## n8n contract

The canonical n8n workflow receives only the event contract:

```json
{
  "source": "supabase",
  "version": 1,
  "eventId": "stable-id",
  "eventType": "order.created",
  "occurredAt": "ISO-8601",
  "data": {}
}
```

n8n must:

- validate the envelope;
- route by event family;
- keep secrets in credentials/runtime configuration;
- remain idempotent at external side-effect boundaries;
- return an explicit execution acknowledgement;
- never become the source of truth for business state.

## Chat contract

`chat_messages.body` is intentionally excluded from the general automation event payload to prevent message content from being unnecessarily exported to external automation. Human chat remains in Supabase. AI assistant messages use the authenticated AI gateway.

## Production gates

A release is not production-ready until there is evidence for:

- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `flutter build web --release`
- `flutter build apk --debug`
- Supabase security advisor review
- real event-bus E2E: domain write -> inbox -> worker -> n8n execution
- duplicate event replay proving idempotency
- chat create/send/realtime read test
- AI read-only tool test
- AI mutation confirmation test
- executor task claim/reconcile test

No build or test is described as passed unless the corresponding command produced evidence.
