-- Delivery lifecycle integrity.
--
-- Two real bugs in the driver path:
--   1) When a driver cancelled (or the order was marked delivered), the reserved
--      inventory was never released or settled, and the driver's
--      `active_order_count` was never decremented. Drivers accumulated a
--      permanently wrong active load and cancelled orders leaked stock.
--   2) `transition_order` let a customer move their own order to ANY status
--      (e.g. 'delivered') with no state-machine or payment checks.
--
-- This migration rewrites the driver update and tightens the transition rules.

-- 1) Driver order updates: only the assigned approved driver, and correctly
--    settle the order + driver load on delivered/cancelled.
create or replace function private.driver_update_order(
  p_order_id text,
  p_status text,
  p_latitude double precision default null,
  p_longitude double precision default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text := auth.uid()::text;
  v_order public.orders%rowtype;
  v_updated integer;
  v_is_terminal boolean;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if not exists (select 1 from public.drivers d where d.uid = v_uid and d.approved) then
    raise exception 'driver_not_approved';
  end if;
  if p_status not in ('assigned','picked_up','out_for_delivery','on_the_way','delivered','cancelled') then
    raise exception 'invalid_delivery_status';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id and driver_id = v_uid
  for update;
  if not found then raise exception 'order_not_assigned_to_driver'; end if;

  v_is_terminal := coalesce(v_order.delivery_status, '') in ('delivered','cancelled');

  update public.orders
  set delivery_status = p_status,
      status = case
        when p_status = 'delivered' then 'delivered'
        when p_status = 'cancelled' then 'cancelled'
        else status
      end,
      driver_location = case
        when p_latitude is not null and p_longitude is not null
          then jsonb_build_object('latitude', p_latitude, 'longitude', p_longitude)
        else driver_location
      end,
      metadata = case
        when p_status = 'cancelled'
          then coalesce(metadata, '{}'::jsonb) || jsonb_build_object('inventory_status','released')
        else metadata
      end,
      updated_at = now()
  where id = p_order_id;
  get diagnostics v_updated = row_count;

  -- A terminal driver update frees the driver and settles inventory once.
  if v_updated > 0 and not v_is_terminal and p_status in ('delivered','cancelled') then
    update public.drivers
    set active_order_count = greatest(0, active_order_count - 1), updated_at = now()
    where uid = v_uid;

    if p_status = 'cancelled' then
      perform public.release_order_inventory(p_order_id);
    end if;
  end if;

  return jsonb_build_object('ok', v_updated > 0, 'order_id', p_order_id, 'status', p_status);
end;
$$;

revoke all on function private.driver_update_order(text,text,double precision,double precision) from public, anon;
grant execute on function private.driver_update_order(text,text,double precision,double precision) to authenticated, service_role;

-- Public wrapper stays invoker-only; the private function is the definer.
create or replace function public.driver_update_order(
  p_order_id text,
  p_status text,
  p_latitude double precision default null,
  p_longitude double precision default null
)
returns jsonb
language sql
set search_path = ''
as $$ select private.driver_update_order(p_order_id,p_status,p_latitude,p_longitude) $$;

revoke all on function public.driver_update_order(text,text,double precision,double precision) from public, anon;
grant execute on function public.driver_update_order(text,text,double precision,double precision) to authenticated, service_role;

-- 2) Order transitions: keep merchant rules, and add customer/driver whitelists
--    so a customer can only cancel an unpaid, non-terminal order.
create or replace function private.transition_order_internal(
  p_order_id text,
  p_status text,
  p_delivery_status text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
  v_uid text;
  v_is_customer boolean := false;
  v_is_driver boolean := false;
  v_is_merchant boolean := false;
  v_is_staff boolean := false;
  v_metadata jsonb;
begin
  v_uid := auth.uid()::text;
  if v_uid is null then raise exception 'not authenticated'; end if;

  select o.status, o.metadata into v_status, v_metadata
  from public.orders o where o.id = p_order_id for update;
  if v_status is null then raise exception 'order not found'; end if;

  select exists(
    select 1 from public.stores s join public.orders o on o.id = p_order_id
    where s.owner_id = v_uid and (s.id = o.merchant_id or s.id = any(o.merchant_ids))
  ) into v_is_merchant;
  v_is_customer := v_uid = (select customer_id from public.orders where id = p_order_id);
  v_is_driver := v_uid = (select driver_id from public.orders where id = p_order_id);
  v_is_staff := private.is_platform_staff();

  if not (v_is_customer or v_is_driver or v_is_merchant or v_is_staff) then
    raise exception 'not authorized';
  end if;

  if v_is_merchant and not v_is_staff then
    if not (
      (v_status = 'pending' and p_status in ('accepted','cancelled'))
      or (v_status = 'accepted' and p_status in ('preparing','cancelled'))
      or (v_status = 'preparing' and p_status = 'ready_for_pickup')
      or (v_status = p_status)
    ) then raise exception 'invalid merchant order transition'; end if;

    if p_status in ('accepted','preparing','ready_for_pickup')
       and coalesce(v_metadata ->> 'inventory_status', '') <> 'reserved' then
      raise exception 'inventory_not_reserved';
    end if;
  elsif v_is_driver and not v_is_staff then
    if not (p_status = 'delivered' or p_status = 'cancelled') then
      raise exception 'invalid driver transition';
    end if;
  elsif v_is_customer and not v_is_staff then
    if not (p_status = 'cancelled' and v_status in ('pending','accepted')) then
      raise exception 'invalid customer transition';
    end if;
    if coalesce(v_metadata ->> 'payment_status', '') = 'paid' then
      raise exception 'cannot_cancel_paid_order';
    end if;
  end if;

  if p_status = 'cancelled'
     and exists(
       select 1 from public.inventory_movements im
       where im.order_id = p_order_id and im.movement_type = 'sale_reservation'
     ) then
    perform public.release_order_inventory(p_order_id);
    v_metadata := coalesce(v_metadata, '{}'::jsonb)
      || jsonb_build_object('inventory_status','released');
  end if;

  update public.orders
  set status = p_status,
      delivery_status = coalesce(p_delivery_status, delivery_status),
      metadata = coalesce(v_metadata, metadata),
      updated_at = now()
  where id = p_order_id;
  return true;
end;
$$;

revoke all on function private.transition_order_internal(text,text,text) from public, anon;
grant execute on function private.transition_order_internal(text,text,text) to authenticated, service_role;
