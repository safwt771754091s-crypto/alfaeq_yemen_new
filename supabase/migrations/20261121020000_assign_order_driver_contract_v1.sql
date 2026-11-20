-- Repair the public.assign_order_driver contract.
--
-- Two defects, both from 20260925020000_production_rpc_invoker_wrappers_v2.sql:
--
-- 1. `create or replace function public.assign_order_driver(...) returns boolean`
--    ran against an existing `returns jsonb` definition (20260922190300). Postgres
--    rejects a return-type change in CREATE OR REPLACE, so on a database that
--    replayed the migrations in order this statement aborted the whole file and
--    the invoker wrappers after it were never created.
--
-- 2. The body did `private.assign_order_driver(...)::boolean`, but the private
--    function returns a jsonb object ({"ok":true,...}). jsonb has no cast to
--    boolean, so every courier assignment and every dispatch raised
--    "cannot cast type jsonb to boolean" at runtime.
--
-- Keep `jsonb` as the public return type: it matches the original definition,
-- carries the order/driver ids the callers use, and lets `->>'ok'` report
-- success. `drop function` makes the statement safe on both a fresh replay and
-- an existing production database.

drop function if exists public.assign_order_driver(text, text);

create or replace function public.assign_order_driver(p_order_id text, p_driver_id text)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  return private.assign_order_driver(p_order_id, p_driver_id);
end
$function$;

revoke all on function public.assign_order_driver(text, text) from public, anon;
grant execute on function public.assign_order_driver(text, text) to authenticated;
