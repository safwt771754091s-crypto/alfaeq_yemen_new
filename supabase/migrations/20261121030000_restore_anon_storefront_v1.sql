-- Restore anonymous storefront reads (stores, products, categories, ...).
--
-- 142 RLS policies are written as
--   using ((select private.is_platform_staff()) or <public visibility>)
-- so Postgres evaluates private.is_platform_staff() for the `anon` role before
-- it can decide whether a row is publicly visible. 20261120010000 granted
-- EXECUTE on the function to anon, but USAGE on schema `private` was only ever
-- granted to `authenticated` (20260925020100, 20261004030000). Without schema
-- USAGE the call fails with
--   permission denied for function is_platform_staff
-- which surfaces as HTTP 401 and leaves the whole public storefront unreadable
-- for signed-out visitors.
--
-- Grant the schema and the function to anon. This does not widen data access:
-- is_platform_staff() is a STABLE boolean that only reads the caller's own
-- profile row via auth.uid(), so for anon it returns false and the policy falls
-- through to the public-visibility branch it was written for.

grant usage on schema private to anon;
grant execute on function private.is_platform_staff() to anon;
