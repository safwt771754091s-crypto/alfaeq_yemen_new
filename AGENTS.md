# Alfaeq Yemen — Engineering Harness

This is the production Flutter + Supabase platform for Alfaeq Yemen. Supabase is the source of truth for application data and automation events.

## Startup
1. Read this file.
2. Read `progress.md` and `feature_list.json`.
3. Inspect the smallest relevant module before editing.
4. Work on one feature at a time.
5. Preserve production architecture: Flutter → Supabase → PostgreSQL/RLS → Edge Functions.

## MUST
- MUST treat Supabase production data/contracts as authoritative.
- MUST verify changes before declaring them complete.
- MUST keep code, tests, and documentation consistent in the same logical change.
- MUST record evidence in `progress.md`.
- MUST respect existing RLS, Auth, roles, and event contracts.
- MUST make event-driven changes idempotent where retries are possible.

## MUST NOT
- MUST NOT introduce Firebase/Firestore as a backend.
- MUST NOT replace real Supabase data with mocks or static production fallbacks.
- MUST NOT claim a build/test passed without actual evidence.
- MUST NOT modify unrelated modules while implementing a feature.
- MUST NOT silently change database contracts or event schemas.

## Verification
Minimum production checkpoint:
```bash
flutter pub get
flutter analyze
flutter test
flutter build web --release
flutter build apk --debug
```

For event-driven changes, also verify the affected event producer, consumer, retry/idempotency behavior, and failure path.

## State
- `feature_list.json`: feature scope and completion criteria.
- `progress.md`: current work and evidence.
- `session-handoff.md`: restart instructions for the next session.

## Definition of Done
A feature is done only when implementation, verification evidence, state documentation, and affected contracts are consistent.
