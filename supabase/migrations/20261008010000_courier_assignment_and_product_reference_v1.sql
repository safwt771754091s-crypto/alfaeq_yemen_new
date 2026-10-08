-- Courier assignment fixes + products.reference column (bulk import).
--
-- Problems fixed:
--   1. private.assign_order_driver never updated orders.delivery_status, so an
--      assigned order stayed in 'awaiting_assignment'. The courier app only
--      renders action buttons for assigned/picked_up/out_for_delivery, so the
--      courier saw the order but could not act on it.
--   2. There was no way for the platform staff to list, approve or activate a
--      courier from the app; the drivers table could not be populated, so
--      auto-dispatch always returned "no available courier".
--   3. public.products has no `reference` column, but the in-app bulk import
--      page selects and inserts it, so every import failed.

-- 1. products.reference ------------------------------------------------------
alter table public.products add column if not exists reference text;

create unique index if not exists products_store_reference_uidx
  on public.products (store_id, reference)
  where reference is not null and btrim(reference) <> '';

-- 2. assign_order_driver: move the order into the delivery pipeline ----------
create or replace function private.assign_order_driver(p_order_id text, p_driver_id text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_prev text;
  v_status text;
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

  update public.orders
  set driver_id = p_driver_id,
      -- Only advance the pipeline when the order is not already terminal and
      -- not already past the assignment stage.
      delivery_status = case
        when v_status in ('delivered', 'cancelled') then v_status
        when v_status in ('assigned', 'picked_up', 'out_for_delivery', 'on_the_way')
          and v_prev = p_driver_id then v_status
        else 'assigned'
      end,
      updated_at = now()
  where id = p_order_id;

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
end;
$function$;

-- 3. Courier management RPCs (platform staff only) ---------------------------
create or replace function private.list_couriers()
returns table (
  uid text,
  approved boolean,
  is_online boolean,
  active_order_count integer,
  current_location jsonb,
  last_seen_at timestamptz,
  display_name text,
  email text,
  app_role text
)
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_platform_staff() then
    raise exception 'staff_required';
  end if;
  return query
    select d.uid, d.approved, d.is_online, d.active_order_count,
           d.current_location, d.last_seen_at,
           u.display_name, u.email, u.role
    from public.drivers d
    left join public.users u on u.uid = d.uid
    order by d.is_online desc, d.approved desc, u.display_name;
end;
$function$;

create or replace function private.approve_courier(p_driver_id text, p_approved boolean)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_platform_staff() then
    raise exception 'staff_required';
  end if;
  if p_driver_id is null or btrim(p_driver_id) = '' then
    raise exception 'driver_id_required';
  end if;

  insert into public.drivers (uid, approved, is_online, active_order_count)
  values (p_driver_id, coalesce(p_approved, false), false, 0)
  on conflict (uid) do update
    set approved = coalesce(p_approved, public.drivers.approved),
        -- De-activating a courier also takes them offline.
        is_online = case when coalesce(p_approved, false) then public.drivers.is_online else false end,
        updated_at = now();

  return jsonb_build_object('ok', true, 'uid', p_driver_id, 'approved', coalesce(p_approved, false));
end;
$function$;

-- 4. Public wrappers ---------------------------------------------------------
create or replace function public.list_couriers()
returns table (
  uid text,
  approved boolean,
  is_online boolean,
  active_order_count integer,
  current_location jsonb,
  last_seen_at timestamptz,
  display_name text,
  email text,
  app_role text
)
language sql
security invoker
set search_path to ''
as $$ select * from private.list_couriers() $$;

create or replace function public.approve_courier(p_driver_id text, p_approved boolean)
returns jsonb
language sql
security invoker
set search_path to ''
as $$ select private.approve_courier(p_driver_id, p_approved) $$;

-- 5. Grants ------------------------------------------------------------------
revoke execute on function private.list_couriers() from public, anon;
revoke execute on function private.approve_courier(text, boolean) from public, anon;
revoke execute on function public.list_couriers() from public, anon;
revoke execute on function public.approve_courier(text, boolean) from public, anon;
grant execute on function private.list_couriers() to authenticated;
grant execute on function private.approve_courier(text, boolean) to authenticated;
grant execute on function public.list_couriers() to authenticated;
grant execute on function public.approve_courier(text, boolean) to authenticated;

create index if not exists orders_driver_delivery_idx
  on public.orders (driver_id, delivery_status);
