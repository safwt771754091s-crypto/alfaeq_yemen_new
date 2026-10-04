# Alfaeq Yemen — Engineering Progress

## Current state
- Harness foundation branch: `feat/harness-engineering`
- Production backend contract: Supabase is the source of truth.
- Current automation architecture documented in README: Supabase automation_events → automation-worker → n8n.
- Next engineering target: connect order_service, inventory, and merchant through explicit event contracts.

## Evidence policy
No task is marked complete from intention or code inspection alone. Record the command/result or GitHub Actions evidence here.

## Current task
Connect order, inventory, and merchant through the production Event Bus without moving business truth out of Supabase.

## Implemented
- Added database Event Bus producers for orders, inventory movements, and merchant stores.
- Added explicit event-contract documentation.
- Preserved atomic inventory reservation and its idempotency constraint.
- Preserved the existing automation-worker retry/backoff path.
- Kept privileged RPCs and event producer execution restricted from clients.

## Next
1. Run the production build checkpoint in GitHub Actions.
2. Inspect CI logs for analyze/test/web/APK failures.
3. Verify the migration contract and event routing after CI.

## Last verified
- Harness files exist on `feat/harness-engineering`.
- Event producer migration committed at `e2e2da0407d06fe2fb6cdc676a8ec8dde52cefc3`.
- Event contract documentation committed.
- Fresh CI evidence is still required before marking the integration complete.

## Interactive AI (ذكاء الفائق) — 2026-10-04
- Scope: make the interactive AI path operational, fix runtime defects, and expose the assistant in the customer UI.
- Fixes: pending tool-call lifecycle, AI gateway provider config/URL normalization, Arabic error mapping, home/account/services entries, live cart badge, `ServicesHubPage` scaffold, 11 analyzer warnings.
- Added `test/ai_service_test.dart` covering the dangling tool-call regression.
- Docs: `docs/architecture/ALFAEQ_AI_OPERATIONS_V1.md`.
- Evidence (local, Flutter 3.47.6 / Dart 3.13.5):
  - `flutter analyze` -> No issues found.
  - `flutter test` -> All tests passed (8).
  - `flutter build web --release` -> Built build/web.
- Server action still required: set `AI_BASE_URL`, `AI_API_KEY`, `AI_MODEL` in Supabase and redeploy `ai-gateway`; without them the gateway returns `ai_provider_not_configured` (shown to the user in Arabic).
