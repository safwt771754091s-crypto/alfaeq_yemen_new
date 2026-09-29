# Jev decision engine integration

Alfaeq uses Jev as a typed decision layer for automation events.

## Runtime path

n8n / platform event
→ `ai-event-worker`
→ Jev System One (`TYPESAFE_ENDPOINT`)
→ typed Choice/Noul decisions
→ deterministic Alfaeq policy
→ `ai_tasks` + `ai_activity_log`
→ audit record in `ai_jev_decisions`

Jev assesses the event; Alfaeq code remains responsible for the final side effect.

## Decision pack

`automation_event_v1` asks, in one request:

- `event_class`: operational category
- `priority`: low / normal / high / urgent
- `needs_human_review`: Noul
- `prompt_injection`: Noul
- `secret_exfil`: Noul

If Jev is unavailable or `TYPESAFE_API_KEY` is not configured, the worker uses its deterministic event-type fallback. Automation therefore does not stop merely because the decision provider is unavailable.

## Required Supabase secrets

Set these as Edge Function secrets; never put them in Flutter, GitHub source, or n8n payloads:

- `TYPESAFE_API_KEY` — required for live Jev decisions.
- `TYPESAFE_MODEL` — optional; defaults to `jev-latest`.
- `TYPESAFE_ENDPOINT` — optional; defaults to `https://api.typesafe.ai/v1/systemone`.

The existing `x-alfaeq-automation-secret` remains the n8n authentication boundary.

## Security

Event payloads are redacted before being sent to Jev for obvious credential fields such as API keys, tokens, secrets, passwords and authorization values. Jev receives decision state only; it never receives Supabase `service_role`.

Jev output is not treated as an instruction. It is data consumed by deterministic Alfaeq code.

## Operational behavior

If Jev marks an event for human review, or the prompt-injection/secret-exfiltration probability reaches the configured action bar, the resulting AI task enters `in_review` with high priority.

The audit table is `public.ai_jev_decisions` with RLS enabled. Writes are performed by the Edge Function using its server-side Supabase client.
