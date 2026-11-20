-- Restore anonymous storefront reads (stores, products, categories, ...).
--
-- 142 RLS policies are written as
--   using ((select private.is_platform_staff()) or <public visibility>)
-- so Postgres evaluates private.is_platform_staff() for the `anon` role before
-- it can decide whether a row is publicly visible. `anon` never held EXECUTE on
-- that function, so the call fails and every signed-out read returns HTTP 401.
--
-- The live error is "permission denied for function is_platform_staff" rather
-- than "... for schema private", which means schema USAGE is already present.
-- Both privileges are granted anyway so the fix does not depend on which one is
-- missing on a given database (a fresh replay creates the schema with no
-- explicit USAGE grant).
--
-- This does not widen data access: is_platform_staff() is a STABLE boolean that
-- only reads the caller's own profile row via auth.uid(), so for anon it
-- returns false and the policy falls through to the public-visibility branch it
-- was written for.

grant usage on schema private to anon;
grant execute on function private.is_platform_staff() to anon;
