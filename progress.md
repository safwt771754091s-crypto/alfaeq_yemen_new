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

## Event Bus reliability — stale inbox claim recovery — 2026-10-09
- Scope: the canonical `automation_event_inbox` path had no recovery for rows stranded in `status='processing'`. `automation-worker` claims a row (status -> `processing`) before calling n8n; if the edge invocation dies mid-flight the row is never re-selected (the worker only reads `status='received'`), so the accepted event is silently dropped. The legacy `automation_events` queue self-heals via `claim_automation_events()`; the inbox had no equivalent.
- Fix: migration `20261009120000_automation_inbox_stale_claim_recovery_v1.sql`
  - adds `automation_event_inbox.processing_at`;
  - adds `public.reap_stale_automation_inbox(p_stale_seconds)` (service_role only) returning stale claims to `received` for a bounded retry;
  - adds `private.automation_inbox_drain_internal()` and a self-healing per-minute `pg_cron` drain (`alfaeq-automation-inbox-drain`) that reaps stale claims and re-invokes `automation-worker`, so retried rows are picked up after their `available_at` backoff (the insert trigger only fires once, at enqueue time).
  - `automation-worker` now stamps `processing_at` on claim and clears it on success/failure.
- Evidence (local PostgreSQL 17.11, stubbed `net.http_post`):
  - stale `processing` claim (attempts 2) -> reaped to `received`, `processing_at` cleared.
  - fresh `processing` claim -> untouched.
  - stale claim with `attempts = 10` -> untouched (attempt limit respected).
  - drain invoked `automation-worker` once with the correct URL and `x-alfaeq-worker-secret`.
  - migration applies cleanly; engineering-gate migration naming/`search_path` checks pass.
- CI evidence (PR #125, all checks successful): Flutter CI analyze-and-test,
  Flutter Build build-web + build-android-debug, Alfaeq Engineering Gates
  contract-and-supply-chain, Security Audit Gate static-security.

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

## Web blank-page root cause: Google CDN dependency — 2026-10-09
- Symptom (user report): the published app "looks deleted" — the page loads but
  shows nothing. Arabic: "الصفحة انحذفت".
- Root cause: `flutter build web` defaulted to `--web-resources-cdn`, so the
  published bundle fetched the CanvasKit renderer from
  `https://www.gstatic.com/flutter-canvaskit/...` and Arabic text fonts from
  `https://fonts.gstatic.com/...`. When those Google domains are unreachable
  (common on Yemeni / restricted networks), the Flutter engine never starts and
  the page stays blank. The HTML shell, `main.dart.js` and the local `canvaskit/`
  directory all return HTTP 200, so the app looks "present but deleted".
- Evidence (Playwright, published Pages URL):
  - Normal load -> `flt-glass-pane` present, login text rendered.
  - gstatic.com blocked -> `flt-glass-pane` absent, body text empty (blank page).
- Fix:
  1. Build web with `--no-web-resources-cdn` (workflow `flutter_build.yml`) so
     CanvasKit ships from the app's own origin.
  2. Bundle an Arabic font (`assets/fonts/NotoSansArabic-Regular.ttf`) and set it
     as the app `fontFamily`, removing the runtime dependency on fonts.gstatic.com.
  3. Extend the `web-smoke` CI job to load the published page both normally and
     with `gstatic.com` blocked, failing if the engine does not start.
- Verification (local, Flutter 3.47.7 / Dart 3.13.x):
  - `flutter analyze` -> No issues found.
  - `flutter test` -> All 72 tests passed.
  - Rebuilt web with `--no-web-resources-cdn`; Playwright with gstatic blocked
    -> `flt-glass-pane` present, Arabic login screen renders, no console errors
    except the expected placeholder Supabase host.
- CI evidence (PR #127, all required checks successful): Flutter CI analyze-and-test,
  Flutter Build build-web + build-android-debug, Alfaeq Engineering Gates
  contract-and-supply-chain, Security Audit Gate static-security. deploy-web /
  web-smoke are main-only and skipped on the PR, so the CDN-blocked smoke
  assertion runs on the next push to main.
