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

## Live AI verification + error-handling fixes — 2026-10-21
- Scope: run the AI path end-to-end against production, then fix the defects found.
- Server config is now complete: `ai-gateway` passes its configuration guards
  (`AI_BASE_URL`/`AI_MODEL` present) and returns real completions. Provider is
  Google Gemini (`gemini-flash-lite-latest`) via the OpenAI-compatible endpoint.
  The free tier returns `429` under load; the gateway maps it to
  `ai_provider_rate_limited`.
- Evidence (live, real `AlfaeqAiService` against the production gateway, opt-in
  `test/live_ai_e2e_test.dart`): name search, barcode search
  (`6281020325937` -> «فول لونا»), wallet, orders, cart, account summary,
  nearby stores, and the confirmation gate all worked. Catalog is priced in
  `SAR`; `get_fx_rates` returns USD base 1 / SAR 3.75 / YER 1537.5, and the AI
  reports the stored SAR price directly (no mislabelling).
- Fixes:
  1. `supabase_flutter.functions.invoke` throws `FunctionsHttpException` on any
     non-2xx, so `UnslothAiService`'s returned-status check never ran and raw SDK
     text (`FunctionsHttpException(status: 429, ...)`) leaked into the UI. Now
     caught and routed through the Arabic mapper (`describeError`, made static).
  2. A confirmation gate on one tool call left sibling calls in the same turn
     unanswered, producing a dangling `tool_call` that the provider rejects on
     the next request. Siblings are now answered
     `not_executed_pending_confirmation`.
  3. `StateError`'s `Bad state:` prefix no longer leaks — dedicated
     `AiGatewayException` whose `toString()` is the Arabic message.
- Tests: `test/unsloth_ai_service_test.dart` (mapper) and a new
  `test/ai_service_test.dart` case for the sibling-call regression.
- Verification (local, Flutter 3.47.6 / Dart 3.13.5):
  - `flutter analyze` -> No issues found.
  - `flutter test` -> All tests passed (80 + 1 opt-in live test skipped in CI).
  - `flutter build web --release` -> Built build/web.
  - Engineering gates re-checked locally: no Firebase runtime dep, no
    service_role reference in the client tree, migration naming valid.
- Remaining bug (not fixed): `lib/screens/developer_page.dart` still checks
  `r.status` after `functions.invoke` (dead branch, same anti-pattern); failures
  are caught and shown, so it is cosmetic.
- Note: commits are on local branch `fix/ai-gateway-error-mapping` (HEAD
  `0c0a5b0` + the `AiGatewayException` commit). The session's `GITHUB_TOKEN` is
  empty and the embedded push token is rejected (401), so the branch could not
  be pushed and no PR was opened.

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

## Full-platform production readiness audit — 2026-10-23
Scope: inspect the whole platform and prepare it for the final release. Branch
`release/v1.0.9-production-readiness` (2 commits on top of `origin/main` 449f175f).

### Local verification (Flutter 3.47.6 / Dart 3.13.5)
- `flutter analyze` -> No issues found.
- `flutter test` -> 93 pass, 1 skipped (opt-in live AI e2e).
- `flutter build web --release --no-web-resources-cdn --base-href /alfaeq_yemen_new/`
  -> Built build/web; local `build/web/canvaskit/` present (no gstatic dependency).
- Engineering/security gates (run locally): no Firebase client dep, no
  `service_role` in client tree, all 96 migration filenames valid, 0
  SECURITY DEFINER functions without `search_path`.
- Android: not buildable in this sandbox (no Android SDK); covered by CI
  (`android-release.yml`, `build_apk.yml`).

### Live backend verification
- REST with the publishable key works; RLS verified: `stores` -> 1 (سوبر الفائق),
  `products` -> 3892, `orders`/`moments`/`notifications` -> 0.
- Sensitive tables (`users`, `wallets`, `wallet_ledger`, `payments`, `orders`,
  `audit_logs`, `ai_tool_audit_logs`, `security_reports`, `chat_messages`,
  `drivers`) return `[]` to the anon key — no anonymous data leak.
- All edge functions are deployed and reachable (correct 401/503/200 config
  guards): ai-gateway, ai-event-worker, automation-event-gateway,
  automation-worker, developer-control, payment-gateway, push-dispatch,
  sheets-catalog-sync, whatsapp-webhook, create-merchant-invite,
  request-password-reset, plus `admin-users` (deployed, 401 invalid_auth).
- Live web (GitHub Pages): index 200, `version.json` = 1.0.8+8, public gallery
  200 (~2.9 MB, 3892 products), local canvaskit + Arabic font 200.

### Fix applied
- `lib/screens/developer_page.dart`: removed three unreachable `r.status` checks
  after `functions.invoke` (the SDK throws `FunctionsHttpException` on non-2xx,
  so the branches never ran and the real error text was lost). Commit 740b655c.

### Remaining blockers / risks (need owner action)
1. **Push blocked**: sandbox `$GITHUB_TOKEN` is empty (len=0); `git push` cannot
   authenticate. Branch is committed locally only. Fix = reprovision the sandbox
   so the GitHub secret re-injects, or supply a PAT.
2. **AI provider quota**: `ai-gateway` is configured (Google Gemini
   `gemini-flash-lite-latest`) but the free tier returns 429 under load; the app
   maps it to Arabic guidance. Consider a paid key / higher quota before launch.
3. **Android signing**: release APK/AAB require `ANDROID_KEYSTORE_BASE64` and the
   keystore secrets in GitHub. Verify they are set before the store release.
4. **Dead code (non-blocking)**: `location_required_page.dart` and
   `smart_dispatch_page.dart` are implemented but unreachable;
   `supabase_data_service.dart` is unreferenced. Left untouched (out of scope).
## Security audit — privilege escalation & storefront outage — 2026-11-20
- Scope: full audit of RLS policies, the RPC surface, and the wallet/money paths
  against the deployed project. Migration:
  `supabase/migrations/20261120010000_security_audit_hardening_v1.sql`.

### Findings (all reproduced before the fix)
1. **CRITICAL — self-minted wallet balance.** `wallets_self_insert`
   (`20260927013000_owner_merchant_wallet_operations.sql`) gated INSERT only on
   `uid = current_user_uid()`. Any signed-in user could insert their own wallet
   with `available_balance = 999999999` and spend it through
   `create_order_paid` / `wallet_transfer` / `pay_mini_program`.
2. **CRITICAL — anonymous storefront outage.** `products` / `stores` /
   `mini_programs` read policies call `private.is_platform_staff()`, which was
   revoked from `anon`. Every logged-out read fails:
   `curl /rest/v1/products` → `42501 permission denied for function
   is_platform_staff` (verified live on both tables).
3. **HIGH — customer email disclosure.** `public.product_reviews` /
   `public.store_reviews` are granted to `anon` and fall back to
   `split_part(u.email,'@',1)`. An anonymous visitor read `secret.person` from
   `secret.person@example.com` on a public product page.
4. **MEDIUM — AI control plane readable by every user.** `ai_agents`,
   `ai_tasks`, `ai_activity_log` used `using (true)` for `authenticated`. Any
   signed-in user read `ai_agents.adapter_config`.
5. **MEDIUM — money primitive granted to clients.**
   `private.wallet_credit_internal` was re-granted to `authenticated`
   (`20260925020100_production_rpc_private_grants_v1.sql`) after the public
   wrapper was revoked.

### Fix
- `wallets_self_insert` now requires a zero balance and zero `version` for
  self-service inserts; staff keep unrestricted insert.
- `grant execute on function private.is_platform_staff() to anon` — EXECUTE only
  (no schema grant added; `anon` already has USAGE, since the live failure is
  function-level, not schema-level). The predicate only inspects the caller's
  own JWT/`users` row, so policies still gate correctly.
- Review readers fall back to `full_name` / `name` metadata then `'مستخدم'`;
  email is never used.
- AI control plane policies replaced with `private.is_platform_staff()`.
- `wallet_credit_internal` / `wallet_debit_internal` revoked from
  `public, anon, authenticated` (internal callers are SECURITY DEFINER).

### Evidence (local PostgreSQL 17.11 harness reproducing the deployed schema)
Before → after, same exploit script:
- self-insert wallet with 999,999,999 → `INSERT 0 1` (balance 999999999) → **RLS violation**.
- wallet insert with zero balance → allowed → **allowed** (legit path intact).
- version spoof (balance 0, version 5) → allowed → **RLS violation**.
- anon `select from products` → `permission denied for function is_platform_staff` → **1 row**.
- any authenticated user reads `ai_agents` → **1 row with adapter_config** → **0 rows**; staff (`app_role=owner`) → **1 row**.
- anon `product_reviews('p1')->items[0].author_name` → `secret.person` → **`مستخدم`**.
- `private.wallet_credit_internal(...)` as authenticated → **permission denied**.
- Migration re-run → no errors (idempotent).

### Remaining risks (not changed here)
- `master_bank_accounts` is readable by every authenticated user. This is
  intentional (customers must see the account to deposit into), but it means
  deposit account numbers are public to the user base. Needs a product decision,
  not a silent schema change.
- Edge Functions with `verify_jwt = false` (automation-worker, ai-event-worker,
  payment-gateway, push-dispatch, whatsapp-webhook) self-authenticate via
  HMAC/shared secret. Reviewed and left as-is.
