-- Fix two driver RPC defects.
--
-- 1. assign_order_driver had no authorization and no validation: any
--    authenticated user could reassign ANY order to ANY uid, and it reported
--    success even for nonexistent orders/drivers. Dispatch is a staff-only
--    surface (admin/owner/developer), so require is_platform_staff(), validate
--    the order and an approved driver, and keep active_order_count accurate
--    (decrement the previous driver, no double counting).
--
-- 2. driver_update_order always returned {"ok":true} even when no row matched
--    (order missing, or not assigned to the caller). Report the real outcome.

create or replace function private.assign_order_driver(p_order_id text, p_driver_id text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_prev text;
begin
  if not private.is_platform_staff() then
    raise exception 'staff_required';
  end if;
  if p_order_id is null or btrim(p_order_id) = '' then
    raise exception 'order_id_required';
  end if;

  select o.driver_id into v_prev
  from public.orders o
  where o.id = p_order_id
  for update;
  if not found then
    raise exception 'order not found';
  end if;

  if not exists (
    select 1 from public.drivers d where d.uid = p_driver_id and d.approved
  ) then
    raise exception 'driver_not_available';
  end if;

  update public.orders set driver_id = p_driver_id, updated_at = now() where id = p_order_id;

  if v_prev is distinct from p_driver_id then
    if v_prev is not null then
      update public.drivers
      set active_order_count = greatest(0, active_order_count - 1), updated_at = now()
      where uid = v_prev;
    end if;
    update public.drivers
    set active_order_count = active_order_count + 1, updated_at = now()
    where uid = p_driver_id;
  end if;

  return jsonb_build_object('ok', true, 'order_id', p_order_id, 'driver_id', p_driver_id);
end
$function$;

create or replace function private.driver_update_order(
  p_order_id text,
  p_status text,
  p_latitude double precision default null,
  p_longitude double precision default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_updated integer;
begin
  update public.orders
  set delivery_status = p_status,
      status = case when p_status in ('delivered','cancelled') then p_status else status end,
      driver_location = case
        when p_latitude is not null and p_longitude is not null
          then jsonb_build_object('latitude', p_latitude, 'longitude', p_longitude)
        else driver_location
      end,
      updated_at = now()
  where id = p_order_id and driver_id = auth.uid()::text;

  get diagnostics v_updated = row_count;

  return jsonb_build_object('ok', v_updated > 0, 'order_id', p_order_id, 'status', p_status);
end
$function$;

revoke all on function private.assign_order_driver(text, text) from public, anon;
revoke all on function private.driver_update_order(text, text, double precision, double precision) from public, anon;
grant execute on function private.assign_order_driver(text, text) to authenticated;
grant execute on function private.driver_update_order(text, text, double precision, double precision) to authenticated;
