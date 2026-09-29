# Alfaeq Yemen — Engineering Progress

## Current state
- Harness foundation branch: `feat/harness-engineering`
- Production backend contract: Supabase is the source of truth.
- Current automation architecture documented in README: Supabase automation_events → automation-worker → n8n.
- Next engineering target: connect order_service, inventory, and merchant through explicit event contracts.

## Evidence policy
No task is marked complete from intention or code inspection alone. Record the command/result or GitHub Actions evidence here.

## Current task
Build the minimum production Harness without changing application behavior.

## Next
1. Review Harness files.
2. Add event-contract documentation.
3. Inspect order_service, inventory, and merchant implementations.
4. Define producer/consumer/idempotency boundaries.
5. Run the production build checkpoint in GitHub Actions.

## Last verified
Repository structure and README reviewed before adding this harness.
