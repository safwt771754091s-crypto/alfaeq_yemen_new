# Alfaeq Yemen AI Control Plane

This module applies useful Paperclip control-plane concepts to Alfaeq Yemen without importing Paperclip as an application dependency.

## Architecture

- Supabase: persistent source of truth for agents, tasks and audit events.
- n8n: event and automation transport.
- Supabase Edge Functions / trusted workers: future execution layer for AI agents and budget enforcement.
- Flutter: read-oriented operational UI.
- GitHub: source control and CI/CD.

## Core model

1. AI agents have roles, capabilities, manager hierarchy, adapter configuration and monthly budgets.
2. Tasks have a traceable parent hierarchy and explicit lifecycle.
3. Activity events capture provider/model, token usage and cost.
4. Heartbeats are represented by agent heartbeat metadata; execution belongs on trusted server-side workers.
5. Client-side code does not grant administrator privileges or agent execution rights.

## Next integration phase

Connect the existing Alfaeq n8n webhook to a trusted worker that resolves an agent, creates or advances an ai_task, executes the agent, records cost/activity, and requires human approval for sensitive production mutations.
