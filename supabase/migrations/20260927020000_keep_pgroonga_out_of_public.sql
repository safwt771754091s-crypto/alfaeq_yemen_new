-- Keep the production search extension outside the exposed public schema.
-- The production database was migrated by controlled index recreation before
-- recording this idempotent guard migration.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_extension e
    JOIN pg_namespace n ON n.oid = e.extnamespace
    WHERE e.extname = 'pgroonga' AND n.nspname = 'public'
  ) THEN
    RAISE EXCEPTION 'pgroonga must not be installed in public schema';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pgroonga') THEN
    CREATE SCHEMA IF NOT EXISTS extensions;
    CREATE EXTENSION pgroonga WITH SCHEMA extensions;
  END IF;
END
$$;
