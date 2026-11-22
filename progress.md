# Alfaeq Yemen — Engineering Progress

## Current state
- Harness foundation branch: `feat/harness-engineering`
- Production backend contract: Supabase is the source of truth.
- Current automation architecture documented in README: Supabase automation_events → automation-worker → n8n.
- Next engineering target: connect order_service, inventory, and merchant through explicit event contracts.

## Evidence policy
No task is marked complete from intention or code inspection alone. Record the command/result or GitHub Actions evidence here.

## Storefront performance and live security audit — 2026-10-03
- Scope: full platform inspection (audit + test), fixing the storefront request storm and verifying
  the live Supabase security posture. No schema, RLS, or event-contract changes.
- Root causes found:
  1. `FutureBuilder(future: _load())` inside `build()` re-fired catalog queries on every rebuild
     (4 sections/pages). Each query costs ~0.5–1.2 s against the live project.
  2. `select('*')` on `products` sent 265 KB per 200 rows; `metadata` alone is ~700 bytes/row.
  3. `activeProductsPaged` walked pages **serially**: a 3 892-product section took 4 round trips.
  4. `Image.network` decoded full-resolution images into memory with no size hint.
  5. A failed read was cached for the full TTL, keeping callers broken after a transient error.
- Changes: `lib/core/query_cache.dart` (new: in-flight dedupe + TTL memo, failures not cached);
  catalog projection narrowed to columns verified against the live schema; `searchBarcode()` moves
  the barcode lookup server-side (`metadata->>barcode`); paged reads run concurrently once the exact
  count is known; futures hoisted into `State`; `cacheWidth` added to fixed-size thumbnails;
  every product write path now calls `QueryCache.instance.invalidate('catalog.')`.
- Verification evidence:
  - `flutter analyze` → `No issues found!`
  - `flutter test` → `233 passed / 1 skipped` (3 new suites: `query_cache_test`,
    `catalog_projection_test`, `catalog_cache_invalidation_test`)
  - `flutter build web --release` → `✓ Built build/web`
  - Live payload, 200 rows: `select=*` 265 314 B → projection 103 479 B (−61 %).
  - Live schema probe: `products.category`, `products.unit`, `products.original_price`,
    `stores.image_url`, `stores.description`, `stores.rating` **do not exist** — selecting them
    fails the whole request with `42703`, so they are excluded from the projections.
  - Live barcode filter `metadata->>barcode=eq.9556023222758` returns exactly the matching product.
  - Security probe (anon key): `users`, `wallets`, `wallet_transactions`, `orders`, `drivers`,
    `notifications`, `audit_logs`, `user_contacts`, `ai_tasks`, `order_items` all return `[]`.
    Anon `INSERT` into `products`/`stores` → `401 / 42501 row-level security policy`.
    Anon upload to the `media` bucket → `403 AccessDenied`. Embedded joins leak nothing.
- Shipped: PR #231, squash-merged as `25646163`.
  - PR checks: analyze-and-test, build-web, build-android-debug, static-security,
    contract-and-supply-chain → all success.
  - Post-merge `main` checks: build, build-web, build-android-debug, android-release,
    analyze-and-test, deploy-web, web-smoke, smoke-critical-path → all success.
  - Live: `.../alfaeq_yemen_new/` → 200, `main.dart.js` → 200 (4 831 635 B).
  - Known pre-existing failure, unrelated to this change: `Supabase Preview` fails on
    `main` with "Remote migration versions not found in local migrations directory"
    (same failure at the previous commit `96018146`). It is skipped on pull requests.

### Follow-up: home page over-fetch — 2026-10-03
- The featured grid renders **12** cards but requested **200** rows and discarded 188 in Dart.
- Fix: `activeProducts(inStockOnly: true)` pushes the filter into Postgres as
  `stock_base=gt.0` (a real column, verified), and the call now asks for `limit: 12`.
- Measured live against the production project, same projection:

  | request | bytes | time |
  |---|---|---|
  | 200 rows (before) | 103 479 | 0.41 s |
  | 12 rows (after) | 12 408 | 0.24 s |

  **88 % smaller** on the heaviest storefront read.
- Safety check on the filter: all 3 892 active rows have `stock_base > 0` and none is null,
  so the server-side filter returns the same set the Dart filter did. The previous code had a
  fallback to the unfiltered list when everything was out of stock; with 3 892 in stock that
  branch was already dead, and it is now gone rather than left to mislead.
- Guards added: `catalog_projection_test.dart` pins the limit and the server-side filter, and
  `security_architecture_test.dart` no longer asserts the old `limit: 200`. Proven by reverting
  the fix — the new test fails, so it is a real guard and not a tautology.
- Verified: `flutter analyze` clean, **235 tests passed** / 1 skipped,
  `flutter build web --release` built, and a live query returns 12 active in-stock rows.

### Image delivery: decode size and storage cache headers — 2026-10-03
- Supabase image transformation is off on this tenant (`403 FeatureNotEnabled`), so thumbnails
  cannot be derived per request. Two levers were available instead.

**1. Decode at display size (the larger win).** Measured real dimensions from the live bucket:

| image | bytes | decoded RGBA |
|---|---|---|
| 1080x1080 webp | 80 240 | **4.45 MB** |
| 1080x1080 webp | 80 700 | 4.45 MB |
| 1000x950 jpeg | 69 227 | 3.71 MB |
| 962x961 jpeg | 84 936 | 3.61 MB |

A grid cell renders at roughly 150 px, so a 4.45 MB buffer was being allocated per card.
Only 4 of 21 `Image.network` sites passed `cacheWidth`; the other 17 decoded at full size.
Added `cacheWidth` to all 17, sized to the rendered box (grids 480, list thumbs 144-162,
hero/detail 720-1200):

- 8 sampled product cards: **19.7 MB -> 6.5 MB** decoded (**-67 %**)
- worst single image: **4.45 MB -> 0.88 MB**
- 12-card home grid of 1080 px images: **53 MB -> 10.5 MB**

**2. Storage cache headers.** Sampled 60 live product images:

| cache-control | count |
|---|---|
| none | 21 |
| `private, no-cache` | 18 |
| cacheable (`max-age`, public) | 8 |

Measured the cost of `no-cache`: conditional GETs return **304 with 0 bytes** in 67-117 ms, so
the price is one round trip per image, not a re-download. Real but smaller than the decode win.
- `official_accounts_service.uploadImage` was the one uploader of nine setting **no**
  `cacheControl`; it now sets `31536000`. New covers will be served cacheable.
- Objects already uploaded keep their stored metadata; changing them needs a re-upload, which
  is not possible from the client with anon credentials (RLS denies writes). Not attempted.

**Guards** (`test/image_decode_size_test.dart`, both proven to fail on regression):
- every `Image.network` must pass `cacheWidth`
- every `uploadBinary` must pass `cacheControl`

Verified: `flutter analyze` clean, **237 tests passed** / 1 skipped, `flutter build web --release`.
Merged as PR #234 -> `3600235a`. All CI green on `main` except the pre-existing `Supabase Preview`
failure; live deploy run succeeded at that SHA and the served `main.dart.js` changed size
(4 831 863 -> 4 831 898 B), confirming the new build is live.

### Investigated and rejected: image thumbnails
- Supabase on-the-fly resizing (`/storage/v1/render/image`) returns
  `403 FeatureNotEnabled — feature not enabled for this tenant`. Image transformation is a paid
  add-on and is off, so thumbnails cannot be produced server-side.
- Pre-generating thumbnails was rejected for now: it needs a schema change plus a backfill
  across 2 341 active images, and the current upload paths do not set a durable
  `cache-control`, so the gain would be partly undone by re-downloads.
- Also measured: 1 551 of 3 892 active products (40 %) have an **empty string** `image_url`
  (not NULL). The storefront already renders a placeholder for that case, so it is not a bug,
  but it is worth a data-quality pass in the merchant flow.

## Public platform page (منصة الفائق يمن) — 2026-11-07
- Scope: add a public, Arabic RTL landing page that presents the whole platform (marketplace, delivery,
  wallet, QR pay, moments/video, Arabic AI, mini-programs, merchant/driver onboarding) and links to the
  existing web app, download page, catalog, and privacy policy.
- Change: `store/site/platform.html` (new, self-contained, no build step). Published at
  `.../alfaeq_yemen_new/store/platform.html` by adding it to the "Publish store pages" copy list in
  `.github/workflows/flutter_build.yml`. Linked from `store/site/index.html` and from README public links.
- Verification (local, static preview served over HTTP mirroring the Pages layout):
  - HTML parse: no unclosed/stray tags (`html.parser` walk).
  - Layout probe at 390px and 1440px: `overflowX=false`, all images loaded, webfonts
    (Reem Kufi / Tajawal) reported loaded by `document.fonts.check`.
  - Internal links 200: `/store/platform.html`, `/store/`, `/store/privacy.html`, `/store/share.html`,
    `/catalog/`, `/`, and the three PNG assets.
- No Flutter/lib, migration, or credential changes; engineering gates unaffected.

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

## Delete-path fixes — D1/D2 (2026-11-21, same PR #227)

Follow-up requested alongside the security audit: fix the deletion problems
(اشكاليات الحذف). Two defects were reproduced against the deployed project
before any change, then fixed and re-verified.

### D1 CRITICAL — reactions could be added but never removed
`public.message_reactions` was created with `revoke all ... from anon`, but the
shipped grant for `authenticated` was `select, insert` only — DELETE was never
granted. Every toggle-off failed with `42501`, so a reaction was permanent once
added.

- Live reproduction: `DELETE /rest/v1/message_reactions?...` →
  `{"code":"42501","hint":"Grant the required privileges to the current role
  with: GRANT SELECT, DELETE ON public.message_reactions"}`.
- Fix: `grant delete on table public.message_reactions to authenticated;`
  The row policy already restricts deletes to `user_id = auth.uid()::text`, so
  no new access is exposed — the policy simply could never be evaluated before.

### D2 HIGH — "deleted" media stayed publicly readable
`MomentsService.deleteMoment` and `ReelsService.deleteReel` deleted only the
row. The photo/video objects stayed in the public `moments` / `reels` buckets,
so a deleted post's media remained readable by anyone holding the URL.

- Live reproduction: the orphaned moments object returned `HTTP 200 image/jpeg`
  from `/storage/v1/object/public/moments/...` with no credentials, while the
  owning row was already gone (`moments` rows: 0).
- Fix: both services now resolve their media paths from the row and call
  `storage.from(bucket).remove(paths)` after the row is deleted (best-effort —
  a storage error must not resurrect an already-committed delete).
- Migration re-creates the owner-scoped `moments_media_delete` /
  `reels_media_delete` storage policies idempotently so the cleanup cannot
  silently no-op if a policy was ever dropped.

### Silent no-op deletes (root cause behind "الحذف لا يعمل")
PostgREST answers `200`/`204` with an empty body when RLS filters the target
row, so a *refused* delete looked like a successful one in the UI.
Verified live: anon `DELETE /rest/v1/moments?id=eq.<uuid>` → `200 []`.

- All four delete paths now use `.delete().eq(...).select('id')` and raise when
  the returned list is empty, so the UI reports the refusal instead of
  refreshing as if the row were gone: `MomentsService.deleteMoment`,
  `ReelsService.deleteReel`, `PublicContentService.deleteUpdate`, and the
  reaction toggle in `GroupChatPage._toggleReaction`.
- Moment/reel deletion additionally checks the loaded row's `author_id` before
  deleting, giving a clear message instead of a generic failure.

### Evidence (local PostgreSQL 17 harness, `/tmp/vh2`)
Same script before → after:
- own reaction delete as `authenticated` → `ERROR: permission denied for table message_reactions` → **`DELETE 1`**.
- remaining reactions → **1** → **0**.
- own `moments` + `reels` storage object delete → **2 remaining** → **0 remaining**.
- another user's object delete attempt → **still present** → **still present** (guard intact).
- migration re-run → no errors (idempotent).

### Verification
- `flutter analyze` — no issues.
- `flutter test` — 216 passed / 1 skipped (includes 8 new cases in
  `test/delete_path_hardening_test.dart`).
- `flutter build web --release` — built successfully.
- `flutter build apk --debug` — not run locally (no Android SDK in this
  sandbox); covered by the `build-android-debug` CI job.

---

## 2026-11-21 — Full platform audit, storefront restored, dispatch repaired (PR #229)

### Live audit (production REST API, public client key)

Probed every sensitive table with the `anon` role:

| Result | Tables |
|---|---|
| `200`, zero rows (RLS correct) | `users`, `wallets`, `orders`, `order_items`, `drivers`, `wallet_transactions`, `moments`, `notifications`, `audit_logs`, `media_assets`, `user_contacts` |
| `401 permission denied for function is_platform_staff` | `stores`, `products` |

The public storefront was **unreadable for every signed-out visitor**.

### Root cause — schema USAGE, not the function grant

142 RLS policies are written as
`using ((select private.is_platform_staff()) or <public visibility>)`, so
Postgres evaluates the predicate before deciding a row is public.
`20261120010000` granted `EXECUTE` on the function to `anon`, but `USAGE` on
schema `private` was only ever granted to `authenticated`
(`20260925020100`, `20261004030000`). The earlier fix could never take effect.

### Fixes shipped

- `20261121030000_restore_anon_storefront_v1.sql` — grants schema `USAGE` and
  `EXECUTE` on `private.is_platform_staff()` to `anon`. No table grant is
  added. Safe: the predicate is `STABLE`, reads only the caller's own profile
  via `auth.uid()`, and returns `false` for `anon`, so the policy falls
  through to its public-visibility branch.
- `20261121020000_assign_order_driver_contract_v1.sql` — `public.assign_order_driver`
  was `jsonb` in `20260922190300` and redefined as `boolean` with
  `CREATE OR REPLACE` in `20260925020000`. Postgres rejects a return-type
  change, so on a clean replay that statement aborted the file and the
  remaining invoker wrappers were never created. The body also did
  `::boolean` on a jsonb object, which has no cast, breaking every courier
  assignment and auto-dispatch. The new migration drops first and returns the
  private result unchanged as `jsonb`.

### Audit results that needed no change

- `SECURITY DEFINER` without a locked `search_path`: **0**
- Tables with RLS disabled: **0** (47 tables checked; `private` was a regex
  false positive on the schema name)
- Net grants to `anon`: **6**, all intentional
- Secrets in git history or tracked files: **none**. The Android keystore lives
  only in the gitignored `.secrets-backup/` and was never committed.

### Verification

- `flutter analyze` — no issues.
- `flutter test` — 223 passed / 1 skipped (7 new in
  `test/storefront_and_dispatch_contract_test.dart`).
- PR #229 — all 10 CI checks green (`analyze-and-test`, `build-web`,
  `build-android-debug`, `static-security`, `contract-and-supply-chain`).
  Merged as `fa88311c`.

### BLOCKED — migrations are not applied to production

`apply-migrations.yml` fails at its first step:
`SUPABASE_DB_URL is not set`. No repo secret exists for it, so **no migration
can reach the database from CI**. The `SUPABASE_ACCESS_TOKEN` in this
environment is not a valid Management API token (`401 JWT could not be
decoded`), and policy forbids using a service-role/secret key.

Consequence: `20261120010000` (F1 wallet minting, F3 review email leak),
`20261121010000` (delete paths), and both migrations above are on `main` but
**not live**. The storefront still returns 401 and the wallet-minting fix is
not active in production.

Owner action required — either:
1. add `SUPABASE_DB_URL` as a repo secret, then run **Actions -> Apply
   Migrations** with the four files, or
2. paste each file into the Supabase **SQL Editor** (they are additive and
   idempotent, so order does not matter).

## 2026-11-21 — migrations applied to production, storefront restored

The blocked apply is resolved. The four pending migrations are now live on
`alfaeq_yemen_prod` (region `ap-northeast-1`, Tokyo).

### How it was unblocked

Four `apply-migrations` dispatches failed on the *value* of `SUPABASE_DB_URL`,
never on the SQL: a project URL (49 chars), the project ref alone (20), then the
database password twice (88). The password was rejected by the server, so the
workflow could not authenticate. Applied instead through the Supabase **SQL
Editor** using `supabase/apply-all-pending.sql` — the four files wrapped in one
`begin; ... commit;` — which returned `Success. No rows returned`.

### Live verification (anon key, after apply)

| Probe | Before | After |
|---|---|---|
| `GET /rest/v1/stores` | `401 42501` | `200`, real rows |
| `GET /rest/v1/products` | `401 42501` | `200`, real rows |
| `POST /rest/v1/wallets` (balance 999999) | — | `401`, RLS violation |
| `POST /rpc/product_reviews` | — | `200`, no email in payload |
| `POST /rpc/assign_order_driver` | `404 PGRST202` | exists; `401` for anon (correct) |

Anon sweep across `users`, `wallets`, `orders`, `drivers`,
`wallet_transactions`, `notifications`, `audit_logs`, `media_assets`,
`user_contacts`, `ai_agents`, `ai_tasks`, `ai_activity_log`: all `200` with zero
rows. RLS holds.

`categories` returns `404 PGRST205` (table absent) — pre-existing, unrelated to
this work.

### Root cause correction

The live error was `permission denied for function is_platform_staff`, not
`... for schema private`, which means `anon` already held USAGE on schema
`private` and only EXECUTE was missing. `20261121030000` grants both, so it holds
either way; the comment in that file now states this correctly.

### Workflow hardening (PR #230)

`apply-migrations.yml` now runs in the `Production` environment (environment
secrets were invisible to a job that names none), accepts a bare password and
builds the URI itself, probes the project's own pooler region first, reports a
per-host reason, and no longer echoes any part of the secret — an earlier
message printed 12 characters of the password into the run log.

### Verification

- `flutter analyze` -> No issues found
- `flutter test` -> 223 passed, 1 skipped
- CI on PR #229 -> 10/10 green, merged `fa88311c`
