# Session Handoff

## Objective
Continue production engineering of Alfaeq Yemen without relying on chat history.

## Read first
1. AGENTS.md
2. progress.md
3. feature_list.json
4. README.md

## Current position
The Harness foundation has been added on branch `feat/harness-engineering`. The next task is event-bus integration for order, inventory, and merchant.

## Do not assume
Do not assume builds, tests, migrations, or integrations passed unless fresh evidence is recorded in progress.md or GitHub Actions.

## Next action
Inspect the existing event/automation tables, services, and Supabase functions; document the actual contracts before changing producers or consumers.
