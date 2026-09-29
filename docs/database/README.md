# Alfaeq database engineering with drawDB

## Source of truth

The production PostgreSQL schema in Supabase remains authoritative. The generated DBML snapshot in
`alfaeq_supabase_production.dbml` is the visualization/design artifact for drawDB.

## Current production snapshot

- Supabase project: `alfaeq_yemen_prod`
- PostgreSQL: 17
- Public tables captured: 47
- Foreign-key relationships captured: 23
- Snapshot date: 2026-09-29

## Core domain

`users -> stores -> products -> orders -> order_items`

Operational extensions include:

- drivers / delivery_events
- payments / payment_providers
- platform_accounts / account_members
- automation_event_inbox / automation_import_jobs
- AI agents / tasks / activity / decision audit

## How drawDB is used

1. Open the drawDB editor.
2. Import the DBML snapshot or convert it through drawDB's supported import flow.
3. Review relationships and cardinality before changing migrations.
4. Keep production migrations under `supabase/migrations/` as the authoritative change history.
5. Regenerate the snapshot after material schema changes.

## Event architecture

The database is not replaced by drawDB. drawDB documents the schema; the transactional event boundary remains in Supabase.

The current order path is:

`orders INSERT -> order.created -> automation_event_inbox -> automation workers/n8n`

The event inbox is idempotent by `event_id`, and inventory reservation remains a server-side transactional operation.

## AI / MCP opportunity

The upstream drawDB project now has a separate read-only MCP server. It can expose diagrams, tables, columns and relationships to AI agents. This is useful for schema-aware engineering, but it must remain read-only; production writes stay behind reviewed Supabase migrations/RPCs.

## Safety

Do not put Supabase `service_role` keys, drawDB API keys, or other secrets in Flutter/web source, DBML files, or public documentation.
