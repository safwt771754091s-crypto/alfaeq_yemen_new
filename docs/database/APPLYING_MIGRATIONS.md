# Applying migrations

Production PostgreSQL in Supabase is the source of truth. Files under
`supabase/migrations/` are the authoritative change history and are **additive**:
they never drop or rewrite existing objects.

CI does **not** apply migrations. Pick one of the paths below.

## 1. Supabase SQL Editor (no tooling)

1. Open the Supabase dashboard for the project.
2. Go to **SQL Editor -> New query**.
3. Paste the migration file contents and click **Run**.

Good for one-off, attended changes. Paste the raw file from GitHub:

```
https://raw.githubusercontent.com/safwt771754091s-crypto/alfaeq_yemen_new/main/supabase/migrations/<file>.sql
```

## 2. GitHub Actions — Apply Migrations (recommended)

`.github/workflows/apply-migrations.yml` is a manual, opt-in workflow.

One-time setup: add a repo secret `SUPABASE_DB_URL` (Supabase ->
Project Settings -> Database -> Connection string -> URI). The workflow never
prints it.

Then: **Actions -> Apply Migrations -> Run workflow**. It defaults to the two
additive feature migrations from 2026-10-25 and accepts a space-separated
`files` input plus a `dry_run` toggle.

The workflow refuses any path outside `supabase/migrations/*.sql` and stops on
the first SQL error (`ON_ERROR_STOP=1`).

## 3. Supabase CLI (local machine)

```
supabase link --project-ref <ref>
supabase db push
```

Or apply a single file:

```
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/<file>.sql
```

## Verifying a migration landed

Tables created by a migration answer `200` over PostgREST with the anon key;
missing tables answer `404`:

```
curl -s -o /dev/null -w '%{http_code}\n' \
  "https://<ref>.supabase.co/rest/v1/<table>?select=id&limit=1" \
  -H "apikey: <anon-or-publishable>"
```

## Notes

- The `service_role` key can write **rows** through PostgREST but cannot run DDL,
  so it cannot create tables or buckets. Migrations need a DB connection or the
  Management API.
- Storage buckets are created by migrations (`storage.buckets` insert), so apply
  the migration before uploading media to a new bucket.
- RLS policies and function grants are part of the migration; skipping it leaves
  the feature tables unprotected, which is why the Flutter features degrade to an
  empty state until the SQL is applied.
