-- Delivery hand-over, live timestamps, and a per-order event trail.
--
-- The merchant and courier flows could already move an order through
-- assigned -> picked_up -> out_for_delivery -> delivered, but nobody could
-- answer "when?" or "who did what?". This migration adds:
--   * explicit hand-over/transit timestamps on public.orders,
--   * a public.order_delivery_events audit trail written by the same trusted RPCs
--     (so the platform, the customer, the merchant and the courier all see the
--     same history), and
--   * the timestamp + event writes inside the existing definer functions.
--
-- The public RPC wrappers keep their signatures, so the Flutter client does not
-- change shape.

-- 1) Timestamps on the order row -------------------------------------------
alter table public.orders
  add column if not exists merchant_ready_at timestamptz,
  add column if not exists assigned_at timestamptz,
  add column if not exists assigned_by text,
  add column if not exists picked_up_at timestamptz,
  add column if not exists out_for_delivery_at timestamptz,
  add column if not exists delivered_at timestamptz,
  add column if not exists cancelled_at timestamptz;

-- 2) Delivery event trail ---------------------------------------------------
-- A dedicated table owned by this migration. public.delivery_events already
-- exists from the automation event bus with a different shape (id text pk,
-- event_type, driver_id, location, metadata) and a row trigger, so reusing it
-- would collide. Keeping the order journey separate is safer and additive.
create table if not exists public.order_delivery_events (
  id bigserial primary key,
  order_id text not null,
  event text not null,
  actor_uid text,
  actor_role text,
  latitude double precision,
  longitude double precision,
  note text,
  created_at timestamptz not null default now()
);

create index if not exists order_delivery_events_order_idx
  on public.order_delivery_events (order_id, created_at);

alter table public.order_delivery_events enable row level security;

drop policy if exists order_delivery_events_select on public.order_delivery_events;
create policy order_delivery_events_select on public.order_delivery_events
for select using (
  (select private.is_platform_staff())
  or actor_uid = auth.uid()::text
  or exists (
    select 1 from public.orders o
    where o.id = order_id
      and (o.customer_id = auth.uid()::text or o.driver_id = auth.uid()::text)
  )
  or exists (
    select 1 from public.orders o
    where o.id = order_id
      and exists (
        select 1 from public.stores s
        where s.owner_id = auth.uid()::text
          and (s.id = o.merchant_id or s.id = any(o.merchant_ids))
      )
  )
);

-- Events are only ever written by the definer RPCs below.
revoke all on public.order_delivery_events from public, anon, authenticated;
grant select on public.order_delivery_events to authenticated;
grant all on public.order_delivery_events to service_role;
grant usage, select on sequence public.order_delivery_events_id_seq to service_role;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'order_delivery_events'
  ) then
    alter publication supabase_realtime add table public.order_delivery_events;
  end if;
exception when others then null;
end $$;

-- 3) Merchant: stamp the hand-over moment ----------------------------------
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
  v_now timestamptz := now();
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
      merchant_ready_at = case
        when p_status = 'ready_for_pickup' then coalesce(merchant_ready_at, v_now)
        else merchant_ready_at
      end,
      cancelled_at = case
        when p_status = 'cancelled' then coalesce(cancelled_at, v_now)
        else cancelled_at
      end,
      metadata = coalesce(v_metadata, metadata),
      updated_at = v_now
  where id = p_order_id;

  insert into public.order_delivery_events (order_id, event, actor_uid, actor_role)
  values (
    p_order_id,
    case
      when p_status = 'ready_for_pickup' then 'ready_for_pickup'
      when p_status = 'accepted' then 'accepted'
      when p_status = 'preparing' then 'preparing'
      when p_status = 'cancelled' then 'cancelled'
      else p_status
    end,
    v_uid,
    case
      when v_is_staff then 'staff'
      when v_is_merchant then 'merchant'
      when v_is_driver then 'driver'
      else 'customer'
    end
  );

  return true;
end;
$$;

revoke all on function private.transition_order_internal(text,text,text) from public, anon;
grant execute on function private.transition_order_internal(text,text,text) to authenticated, service_role;

-- 4) Courier: stamp assignment and every transit step ----------------------
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
  v_now timestamptz := now();
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
      assigned_at = case
        when p_status = 'assigned' then coalesce(assigned_at, v_now)
        else assigned_at
      end,
      picked_up_at = case
        when p_status = 'picked_up' then coalesce(picked_up_at, v_now)
        else picked_up_at
      end,
      out_for_delivery_at = case
        when p_status in ('out_for_delivery','on_the_way') then coalesce(out_for_delivery_at, v_now)
        else out_for_delivery_at
      end,
      delivered_at = case
        when p_status = 'delivered' then coalesce(delivered_at, v_now)
        else delivered_at
      end,
      cancelled_at = case
        when p_status = 'cancelled' then coalesce(cancelled_at, v_now)
        else cancelled_at
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
      updated_at = v_now
  where id = p_order_id;
  get diagnostics v_updated = row_count;

  if v_updated > 0 then
    insert into public.order_delivery_events
      (order_id, event, actor_uid, actor_role, latitude, longitude)
    values
      (p_order_id, p_status, v_uid, 'driver', p_latitude, p_longitude);
  end if;

  -- A terminal driver update frees the driver and settles inventory once.
  if v_updated > 0 and not v_is_terminal and p_status in ('delivered','cancelled') then
    update public.drivers
    set active_order_count = greatest(0, active_order_count - 1), updated_at = v_now
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

-- 5) Assignment: stamp the moment a courier takes the order ----------------
create or replace function private.assign_order_driver(p_order_id text, p_driver_id text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_prev text;
  v_status text;
  v_new_status text;
  v_now timestamptz := now();
begin
  -- Platform staff may assign to anyone; a courier may accept for themselves.
  if not private.is_platform_staff() then
    if auth.uid()::text is distinct from p_driver_id then
      raise exception 'staff_required';
    end if;
  end if;

  if p_order_id is null or btrim(p_order_id) = '' then
    raise exception 'order_id_required';
  end if;

  select o.driver_id, coalesce(o.delivery_status, '')
    into v_prev, v_status
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

  v_new_status := case
    when v_status in ('delivered', 'cancelled') then v_status
    when v_status in ('assigned', 'picked_up', 'out_for_delivery', 'on_the_way')
      and v_prev = p_driver_id then v_status
    else 'assigned'
  end;

  update public.orders
  set driver_id = p_driver_id,
      delivery_status = v_new_status,
      assigned_at = case
        when v_new_status = 'assigned' and (v_prev is distinct from p_driver_id or assigned_at is null)
          then v_now
        else assigned_at
      end,
      updated_at = v_now
  where id = p_order_id;

  if v_prev is distinct from p_driver_id then
    if v_prev is not null then
      update public.drivers
      set active_order_count = greatest(0, active_order_count - 1), updated_at = v_now
      where uid = v_prev;
    end if;
    update public.drivers
    set active_order_count = active_order_count + 1, updated_at = v_now
    where uid = p_driver_id;

    insert into public.order_delivery_events (order_id, event, actor_uid, actor_role)
    values (p_order_id, 'assigned', auth.uid()::text,
            case when private.is_platform_staff() then 'staff' else 'driver' end);
  end if;

  return jsonb_build_object('ok', true, 'order_id', p_order_id, 'driver_id', p_driver_id);
end;
$function$;

revoke all on function private.assign_order_driver(text,text) from public, anon;
grant execute on function private.assign_order_driver(text,text) to authenticated, service_role;
