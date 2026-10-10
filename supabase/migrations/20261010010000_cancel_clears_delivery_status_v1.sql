-- Cancelling an order must also clear its delivery lifecycle.
--
-- Bug: private.transition_order_internal only ever set
-- `delivery_status = coalesce(p_delivery_status, delivery_status)`. Neither the
-- customer cancellation path nor the merchant cancellation path passes
-- p_delivery_status, so a cancelled order kept delivery_status='pending'.
-- Dispatch/queue screens stream `delivery_status in ('pending',
-- 'awaiting_assignment')`, so cancelled orders kept showing up for couriers as
-- assignable and inflated the pending queue.
--
-- Fix:
--   1) derive delivery_status on cancel inside transition_order_internal;
--   2) a narrow trigger as a safety net so any future code path that sets
--      status='cancelled' also settles delivery_status;
--   3) backfill the already-leaked rows.

-- 1) transition_order_internal: settle delivery_status on cancel.
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
  v_delivery text;
begin
  v_uid := auth.uid()::text;
  if v_uid is null then raise exception 'not authenticated'; end if;

  select o.status, o.metadata, o.delivery_status
    into v_status, v_metadata, v_delivery
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

  -- A cancelled order leaves the delivery lifecycle immediately, unless a
  -- caller explicitly asks for a different delivery status.
  if p_status = 'cancelled' and p_delivery_status is null
     and coalesce(v_delivery, '') not in ('delivered','cancelled') then
    p_delivery_status := 'cancelled';
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

-- 2) Safety net for any other code path that cancels an order.
create or replace function private.settle_delivery_on_cancel()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'cancelled'
     and coalesce(new.delivery_status, '') not in ('cancelled','delivered') then
    new.delivery_status := 'cancelled';
  end if;
  return new;
end;
$$;

drop trigger if exists orders_settle_delivery_on_cancel on public.orders;
create trigger orders_settle_delivery_on_cancel
  before insert or update of status on public.orders
  for each row execute function private.settle_delivery_on_cancel();

-- 3) Backfill rows already leaked by the bug.
update public.orders
set delivery_status = 'cancelled', updated_at = now()
where status = 'cancelled'
  and coalesce(delivery_status, '') not in ('cancelled','delivered');
