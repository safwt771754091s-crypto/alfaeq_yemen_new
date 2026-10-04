-- Fix the checkout blocker: reserve_order_inventory always failed.
--
-- reserve_order_inventory (SECURITY DEFINER) calls begin_operation_snapshot /
-- complete_operation_snapshot. Those are also SECURITY DEFINER, so inside them
-- `current_user` is the function owner (postgres), never 'service_role'. The
-- guard `current_user <> 'service_role'` therefore always raised
-- 'service_role_required', aborting every order before inventory was reserved.
--
-- These functions are not granted to anon/authenticated (EXECUTE is limited to
-- service_role/owner), so the guard added no security. Removing it lets the
-- trusted order path call them while direct client calls remain denied.

create or replace function public.begin_operation_snapshot(
  p_idempotency_key text,
  p_operation_type text,
  p_aggregate_type text,
  p_aggregate_id text,
  p_before_state jsonb
)
returns table(snapshot_id uuid, acquired boolean, status text)
language plpgsql
security definer
set search_path to ''
as $function$
declare v_id uuid; v_status text;
begin
  if coalesce(btrim(p_idempotency_key),'')='' then raise exception 'idempotency_key_required'; end if;
  insert into public.operation_state_snapshots(
    idempotency_key, operation_type, aggregate_type, aggregate_id, before_state, locked_at
  ) values (
    p_idempotency_key, p_operation_type, p_aggregate_type, p_aggregate_id,
    coalesce(p_before_state,'{}'::jsonb), now()
  )
  on conflict (idempotency_key) do nothing
  returning operation_state_snapshots.id, operation_state_snapshots.status into v_id, v_status;
  if v_id is not null then
    return query select v_id, true, v_status;
    return;
  end if;
  select s.id, s.status into v_id, v_status
  from public.operation_state_snapshots s
  where s.idempotency_key=p_idempotency_key
  for update;
  return query select v_id, false, v_status;
end
$function$;

create or replace function public.complete_operation_snapshot(p_snapshot_id uuid, p_after_state jsonb)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
begin
  update public.operation_state_snapshots
     set after_state=coalesce(p_after_state,'{}'::jsonb),
         status='completed', completed_at=now(), locked_at=null, updated_at=now(), error=null
   where id=p_snapshot_id and status='active';
  return found;
end;
$function$;

create or replace function public.revert_operation_snapshot(p_snapshot_id uuid, p_error jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare v_state jsonb;
begin
  select before_state into v_state
  from public.operation_state_snapshots
  where id=p_snapshot_id and status in ('active','completed')
  for update;
  if not found then return null; end if;
  update public.operation_state_snapshots
     set status='reverted', reverted_at=now(), locked_at=null, updated_at=now(),
         error=coalesce(p_error,error)
   where id=p_snapshot_id;
  return v_state;
end;
$function$;

revoke all on function public.begin_operation_snapshot(text, text, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.complete_operation_snapshot(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.revert_operation_snapshot(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.begin_operation_snapshot(text, text, text, text, jsonb) to service_role;
grant execute on function public.complete_operation_snapshot(uuid, jsonb) to service_role;
grant execute on function public.revert_operation_snapshot(uuid, jsonb) to service_role;
