# Alfaeq Yemen Engineering Conventions

## Source of truth
- Supabase PostgreSQL is the production source of truth for transactional data.
- Event-driven boundaries use the existing Supabase event inbox/event bus.
- Flutter UI must not become a second source of truth for orders, inventory, merchant state, or payments.

## Safety
- Never commit secrets, API keys, service-role keys, or production credentials.
- Critical mutations must be transactional and idempotent.
- Inventory/order mutations must use database row locking where concurrent writes are possible.
- Reversible operations should capture real prior state before mutation and retain an auditable compensation record.
- Prefer additive migrations; do not rewrite production history.

## Change workflow
1. Inspect the existing domain and migration before editing.
2. Make the smallest coherent change.
3. Run formatter/static analysis/tests appropriate to the changed area.
4. Verify database migrations against the connected Supabase project when applicable.
5. Review the diff for security, RLS, idempotency, and backward compatibility.
6. Let GitHub Actions provide the final build verdict.

## Architecture
- Auth/RLS -> Users/Roles -> Stores -> Products -> Inventory -> Cart -> Orders -> Merchant -> Driver -> Dispatch -> Tracking -> Payments -> Wallet/Ledger -> Settlement -> Notifications -> Chat -> Automation -> AI -> Services -> Analytics.
- External automation must consume canonical events rather than duplicating business state.
- Compensation is preferred over destructive rollback for already-published external side effects.

## Flutter
- Keep domain logic out of widgets where practical.
- Prefer typed models and explicit async error handling.
- Do not hide production errors with broad catches.
- Arabic/RTL behavior must be tested for user-facing flows.

## AI-assisted development
- Use an architect/reviewer pass for cross-cutting changes.
- Use a focused editor pass for implementation.
- For bounded autonomous repository tasks, prefer a minimal linear agent loop: inspect -> command -> observation -> next command, with explicit step/cost/time limits and an isolated workspace.
- Require lint/test/build evidence before calling a change production-ready.
- Keep AI-generated changes reviewable through Git history and small commits.
- Keep engineering-agent responsibilities separated into agent, conversation/state, tools/skills, workspace, and server/automation boundaries; do not create a monolithic agent layer.
- Give each durable state domain one clear owner: Supabase for product state, the canonical event bus for event state, and the agent conversation for agent-run state.


## Browser automation
- Prefer structured visible-control observations when browser automation can avoid screenshot-first reasoning.
- Browser decisions use typed operations and targets derived from the latest observation.
- Revalidate a target immediately before a browser mutation; never blindly retry a mutation.
- Treat DONE as a request for independent postcondition verification, not proof of success.
- Keep browser credentials in the secret environment and keep live paid-browser checks out of offline CI.
