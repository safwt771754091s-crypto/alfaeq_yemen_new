-- Fix: private.transition_order_internal raised
--   'column reference "uid" is ambiguous' (42702)
-- because the PL/pgSQL variable `uid` collided with public.users.uid in the
-- staff-check subquery. That made EVERY order transition fail, blocking
-- accepted/preparing/ready_for_pickup/delivered/cancelled for customers,
-- merchants, drivers, and staff.
--
-- Renames the local variables with a v_ prefix so they can no longer shadow
-- column names. Behaviour is otherwise unchanged.

create or replace function private.transition_order_internal(
  p_order_id text,
  p_status text,
  p_delivery_status text default null::text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_status text;
  v_uid text;
  v_merchant_authorized boolean := false;
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
  ) into v_merchant_authorized;

  if not (
    v_uid = (select customer_id from public.orders where id = p_order_id)
    or v_uid = (select driver_id from public.orders where id = p_order_id)
    or v_merchant_authorized
    or exists(
      select 1 from public.users u where u.uid = v_uid and
      (coalesce(u.admin,false) or coalesce(u.owner,false) or coalesce(u.developer,false))
    )
  ) then raise exception 'not authorized'; end if;

  if v_merchant_authorized and not (
    (v_status = 'pending' and p_status in ('accepted','cancelled'))
    or (v_status = 'accepted' and p_status in ('preparing','cancelled'))
    or (v_status = 'preparing' and p_status = 'ready_for_pickup')
    or (v_status = p_status)
  ) then raise exception 'invalid merchant order transition'; end if;

  if v_merchant_authorized and p_status in ('accepted','preparing','ready_for_pickup') then
    if coalesce(v_metadata ->> 'inventory_status', '') <> 'reserved' then
      raise exception 'inventory_not_reserved';
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
$function$;
