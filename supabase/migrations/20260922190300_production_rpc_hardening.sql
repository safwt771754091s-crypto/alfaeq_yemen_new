-- Production hardening applied to Supabase project alfaeq_yemen_prod.
-- Keep the public RPCs SECURITY INVOKER; privileged mutation logic lives in private schema.
create schema if not exists private;

-- The current database already contains the internal implementations used below.
-- This migration records the public-surface hardening performed on 2026-09-22.
create or replace function public.create_order(
  p_items jsonb, p_address text, p_payment_method text,
  p_latitude double precision default null, p_longitude double precision default null
) returns text language plpgsql security invoker set search_path=''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'authentication_required' using errcode='28000';
  end if;
  return private.create_order_internal(p_items,p_address,p_payment_method,p_latitude,p_longitude);
end;
$$;

create or replace function public.assign_order_driver(p_order_id text,p_driver_id text)
returns jsonb language sql security invoker set search_path=''
as $$ select private.assign_order_driver(p_order_id,p_driver_id) $$;

create or replace function public.driver_update_location(p_latitude double precision,p_longitude double precision)
returns jsonb language sql security invoker set search_path=''
as $$ select private.driver_update_location(p_latitude,p_longitude) $$;

create or replace function public.driver_update_order(
  p_order_id text,p_status text,p_latitude double precision default null,p_longitude double precision default null
) returns jsonb language sql security invoker set search_path=''
as $$ select private.driver_update_order(p_order_id,p_status,p_latitude,p_longitude) $$;

create or replace function private.ensure_driver_profile()
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_uid text := auth.uid()::text;
begin
  if v_uid is null then raise exception 'unauthenticated'; end if;
  if not (
    coalesce(auth.jwt()->>'app_role','') in ('driver','admin','owner','developer')
    or coalesce((auth.jwt()->>'admin')::boolean,false)
    or coalesce((auth.jwt()->>'owner')::boolean,false)
    or coalesce((auth.jwt()->>'developer')::boolean,false)
  ) then raise exception 'driver_role_required'; end if;
  insert into public.drivers(uid,approved,is_online,active_order_count)
  values(v_uid,false,false,0) on conflict(uid) do nothing;
  return jsonb_build_object('ok',true,'uid',v_uid);
end;
$$;

create or replace function public.ensure_driver_profile()
returns jsonb language sql security invoker set search_path=''
as $$ select private.ensure_driver_profile() $$;

revoke execute on function private.ensure_driver_profile() from public,anon,authenticated;
drop index if exists public.orders_delivery_status_idx;
