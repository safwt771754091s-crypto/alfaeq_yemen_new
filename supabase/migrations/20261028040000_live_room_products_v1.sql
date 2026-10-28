-- Live commerce: a product shelf attached to a live room, so viewers can buy
-- while watching (الشراء أثناء البث).
--
-- The room already exists (live_rooms). This migration only adds the shelf
-- (room <-> product) and the RPCs to manage and read it. Checkout is NOT
-- re-implemented here: the client adds the chosen product to the existing cart
-- and uses the audited create_order / create_order_paid RPCs, so all money
-- movement keeps living in one place.

create table if not exists public.live_room_products (
  room_id uuid not null references public.live_rooms(id) on delete cascade,
  product_id text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  primary key (room_id, product_id)
);

alter table public.live_room_products enable row level security;

-- Readable by anyone who may watch the room; writes go through the host-only
-- RPCs below (SECURITY DEFINER), so no insert/update/delete policy is needed.
drop policy if exists live_room_products_read on public.live_room_products;
create policy live_room_products_read on public.live_room_products
for select to authenticated
using (
  exists (
    select 1 from public.live_rooms r
    where r.id = live_room_products.room_id
      and (r.status <> 'scheduled' or r.host_id = auth.uid() or private.is_platform_staff())
  )
);

-- The shelf as the viewer sees it: live product data, joined to the room.
create or replace function public.live_room_products_list(p_room_id uuid)
returns table (
  product_id text, name text, price numeric, currency text,
  image_url text, stock numeric, store_id text, owner_id text
)
language sql
stable
security definer
set search_path to ''
as $function$
  select p.id, p.name, p.price, p.currency, p.image_url, p.stock, p.store_id, p.owner_id
    from public.live_room_products lp
    join public.products p on p.id = lp.product_id
   where lp.room_id = p_room_id
     and p.status = 'active'
     and exists (
       select 1 from public.live_rooms r
       where r.id = p_room_id
         and (r.status <> 'scheduled' or r.host_id = auth.uid() or private.is_platform_staff())
     )
   order by lp.sort_order, p.name;
$function$;

revoke all on function public.live_room_products_list(uuid) from public, anon;
grant execute on function public.live_room_products_list(uuid) to authenticated;

-- Host adds a product to their own room's shelf.
drop function if exists public.live_room_products_add(uuid, text);
create or replace function public.live_room_products_add(p_room_id uuid, p_product_id text)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if auth.uid() is null then raise exception 'auth_required' using errcode = '28000'; end if;
  if not exists (select 1 from public.live_rooms r where r.id = p_room_id and r.host_id = auth.uid()) then
    raise exception 'not_room_host' using errcode = '42501';
  end if;
  if not exists (select 1 from public.products p where p.id = p_product_id and p.status = 'active') then
    raise exception 'product_not_available';
  end if;
  insert into public.live_room_products(room_id, product_id, sort_order)
  values (
    p_room_id,
    p_product_id,
    (select coalesce(max(sort_order), 0) + 1 from public.live_room_products where room_id = p_room_id)
  )
  on conflict (room_id, product_id) do nothing;
end;
$function$;

revoke all on function public.live_room_products_add(uuid, text) from public, anon;
grant execute on function public.live_room_products_add(uuid, text) to authenticated;

-- Host removes a product from their own room's shelf.
drop function if exists public.live_room_products_remove(uuid, text);
create or replace function public.live_room_products_remove(p_room_id uuid, p_product_id text)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if auth.uid() is null then raise exception 'auth_required' using errcode = '28000'; end if;
  if not exists (select 1 from public.live_rooms r where r.id = p_room_id and r.host_id = auth.uid()) then
    raise exception 'not_room_host' using errcode = '42501';
  end if;
  delete from public.live_room_products where room_id = p_room_id and product_id = p_product_id;
end;
$function$;

revoke all on function public.live_room_products_remove(uuid, text) from public, anon;
grant execute on function public.live_room_products_remove(uuid, text) to authenticated;

-- Realtime so a product added mid-stream appears for viewers immediately.
do $$ begin
  alter publication supabase_realtime add table public.live_room_products;
exception when duplicate_object then null; when undefined_object then null; end $$;
