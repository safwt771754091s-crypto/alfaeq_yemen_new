-- Alfaeq Yemen: order/inventory consistency v4
-- Catalog/order creation no longer mutates stock. Trusted reservation does.
-- Reservation is idempotent; cancellation releases reservation without inflating sold counters.

create or replace function private.create_order_internal(
  p_items jsonb,
  p_address text,
  p_payment_method text,
  p_latitude double precision default null,
  p_longitude double precision default null
) returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_customer_id text := auth.uid()::text;
  v_order_id text := to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS') || substr(md5(random()::text),1,8);
  v_total numeric := 0;
  v_merchant_ids text[] := '{}';
  v_item jsonb;
  v_product public.products%rowtype;
  v_qty numeric;
  v_line_total numeric;
  v_store_owner text;
  v_currency text := null;
begin
  if v_customer_id is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'order_items_required' using errcode = '22023';
  end if;

  insert into public.orders(
    id, customer_id, status, delivery_status, address, latitude, longitude,
    payment_method, total, currency, items, metadata
  )
  values(
    v_order_id, v_customer_id, 'pending', 'awaiting_assignment',
    nullif(trim(p_address), ''), p_latitude, p_longitude,
    nullif(trim(p_payment_method), ''), 0, 'YER', p_items,
    jsonb_build_object('inventory_status','pending_reservation')
  );

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_qty := nullif(v_item->>'quantity','')::numeric;
    if v_qty is null or v_qty <= 0 then
      raise exception 'invalid_quantity' using errcode='22023';
    end if;

    select * into v_product
    from public.products
    where id=v_item->>'product_id' and status='active'
    for update;

    if not found then
      raise exception 'product_not_available:%',v_item->>'product_id' using errcode='P0001';
    end if;

    if coalesce(v_product.stock_base, v_product.stock) <
       coalesce(v_qty * v_product.unit_scale, v_qty) then
      raise exception 'insufficient_stock:%',v_product.id using errcode='P0001';
    end if;

    if v_currency is null then v_currency := coalesce(v_product.currency,'YER');
    elsif v_product.currency <> v_currency then
      raise exception 'mixed_currencies_not_supported' using errcode='22023';
    end if;

    select s.owner_id into v_store_owner from public.stores s where s.id=v_product.store_id;
    if v_store_owner is not null and not (v_store_owner=any(v_merchant_ids)) then
      v_merchant_ids := array_append(v_merchant_ids,v_store_owner);
    end if;

    v_line_total := v_product.price * v_qty;
    v_total := v_total + v_line_total;

    insert into public.order_items(
      order_id, product_id, store_id, name, quantity, quantity_base,
      unit_price, currency, metadata
    )
    values(
      v_order_id, v_product.id, v_product.store_id, v_product.name, v_qty,
      coalesce(v_qty*v_product.unit_scale,v_qty), v_product.price,
      v_product.currency, jsonb_build_object('source','server_priced')
    );
  end loop;

  update public.orders
  set total=v_total,
      currency=coalesce(v_currency,'YER'),
      merchant_ids=v_merchant_ids,
      merchant_id=case when cardinality(v_merchant_ids)=1 then v_merchant_ids[1] else null end,
      updated_at=now()
  where id=v_order_id;

  return v_order_id;
end;
$function$;

create or replace function public.reserve_order_inventory(p_order_id text)
returns table(product_id text, reserved_quantity numeric, stock_before numeric, stock_after numeric)
language plpgsql
security definer
set search_path = public
as $function$
declare
  item record; p record; qty numeric; qty_base numeric;
  before_stock numeric; after_stock numeric; already_reserved boolean; v_status text;
begin
  if p_order_id is null or btrim(p_order_id) = '' then raise exception 'order_id is required'; end if;

  select status into v_status from public.orders where id=p_order_id for update;
  if not found then raise exception 'order not found: %', p_order_id; end if;
  if v_status not in ('pending','confirmed','accepted','preparing','ready_for_pickup') then
    raise exception 'order_not_reservable:%',v_status;
  end if;

  for item in
    select oi.product_id, sum(oi.quantity) quantity,
           sum(coalesce(oi.quantity_base,oi.quantity)) quantity_base
    from public.order_items oi
    where oi.order_id=p_order_id and oi.product_id is not null
    group by oi.product_id order by oi.product_id
  loop
    select * into p from public.products where id=item.product_id for update;
    if not found then raise exception 'product not found: %',item.product_id; end if;

    qty:=item.quantity; qty_base:=item.quantity_base;
    if qty<=0 or qty_base<=0 then raise exception 'invalid quantity for product %',item.product_id; end if;

    select exists(
      select 1 from public.inventory_movements im
      where im.order_id=p_order_id and im.product_id=item.product_id
        and im.movement_type='sale_reservation'
    ) into already_reserved;

    if already_reserved then
      product_id:=item.product_id; reserved_quantity:=qty;
      stock_before:=p.stock; stock_after:=p.stock; return next; continue;
    end if;

    if coalesce(p.stock_base,p.stock)<qty_base then
      raise exception 'insufficient stock for product %: requested %, available %',
        item.product_id,qty_base,coalesce(p.stock_base,p.stock);
    end if;

    before_stock:=p.stock; after_stock:=greatest(0,p.stock-qty);

    update public.products
    set stock=after_stock,
        stock_base=greatest(0,coalesce(stock_base,stock)-qty_base),
        updated_at=now()
    where id=item.product_id;

    insert into public.inventory_movements(
      product_id,order_id,quantity,quantity_base,
      stock_before_base,stock_after_base,movement_type
    )
    values(
      item.product_id,p_order_id,qty,qty_base,
      coalesce(p.stock_base,p.stock),
      greatest(0,coalesce(p.stock_base,p.stock)-qty_base),
      'sale_reservation'
    );

    product_id:=item.product_id; reserved_quantity:=qty;
    stock_before:=before_stock; stock_after:=after_stock; return next;
  end loop;
end;
$function$;

create or replace function public.release_order_inventory(p_order_id text)
returns table(product_id text, released_quantity numeric, stock_before numeric, stock_after numeric)
language plpgsql
security definer
set search_path = public
as $function$
declare m record; p record; before_stock numeric; after_stock numeric;
begin
  if p_order_id is null or btrim(p_order_id)='' then raise exception 'order_id is required'; end if;

  for m in
    select product_id,sum(quantity) quantity,sum(quantity_base) quantity_base
    from public.inventory_movements
    where order_id=p_order_id and movement_type='sale_reservation'
      and not exists (
        select 1 from public.inventory_movements r
        where r.order_id=p_order_id and r.product_id=inventory_movements.product_id
          and r.movement_type='sale_reservation_release'
      )
    group by product_id order by product_id
  loop
    select * into p from public.products where id=m.product_id for update;
    if not found then raise exception 'product not found: %',m.product_id; end if;

    before_stock:=p.stock; after_stock:=coalesce(p.stock,0)+coalesce(m.quantity,0);

    update public.products
    set stock=after_stock,
        stock_base=coalesce(stock_base,0)+coalesce(m.quantity_base,m.quantity),
        updated_at=now()
    where id=m.product_id;

    insert into public.inventory_movements(
      product_id,order_id,quantity,quantity_base,
      stock_before_base,stock_after_base,movement_type
    )
    values(
      m.product_id,p_order_id,m.quantity,m.quantity_base,
      coalesce(p.stock_base,p.stock),
      coalesce(p.stock_base,p.stock)+coalesce(m.quantity_base,m.quantity),
      'sale_reservation_release'
    );

    product_id:=m.product_id; released_quantity:=m.quantity;
    stock_before:=before_stock; stock_after:=after_stock; return next;
  end loop;
end;
$function$;

revoke all on function public.reserve_order_inventory(text) from public,anon,authenticated;
grant execute on function public.reserve_order_inventory(text) to service_role;
revoke all on function public.release_order_inventory(text) from public,anon,authenticated;
grant execute on function public.release_order_inventory(text) to service_role;

create or replace function private.transition_order_internal(
  p_order_id text,p_status text,p_delivery_status text default null
) returns boolean
language plpgsql security definer set search_path=''
as $function$
declare current_status text; uid text; merchant_authorized boolean:=false; v_metadata jsonb;
begin
  uid:=auth.uid()::text; if uid is null then raise exception 'not authenticated'; end if;

  select o.status,o.metadata into current_status,v_metadata
  from public.orders o where o.id=p_order_id for update;
  if current_status is null then raise exception 'order not found'; end if;

  select exists(
    select 1 from public.stores s join public.orders o on o.id=p_order_id
    where s.owner_id=uid and (s.id=o.merchant_id or s.id=any(o.merchant_ids))
  ) into merchant_authorized;

  if not (
    uid=(select customer_id from public.orders where id=p_order_id)
    or uid=(select driver_id from public.orders where id=p_order_id)
    or merchant_authorized
    or exists(select 1 from public.users u where u.uid=uid and
      (coalesce(u.admin,false) or coalesce(u.owner,false) or coalesce(u.developer,false)))
  ) then raise exception 'not authorized'; end if;

  if merchant_authorized and not (
    (current_status='pending' and p_status in ('accepted','cancelled'))
    or (current_status='accepted' and p_status in ('preparing','cancelled'))
    or (current_status='preparing' and p_status='ready_for_pickup')
    or (current_status=p_status)
  ) then raise exception 'invalid merchant order transition'; end if;

  if merchant_authorized and p_status in ('accepted','preparing','ready_for_pickup')
     and coalesce(v_metadata->>'inventory_status','') <> 'reserved' then
    raise exception 'inventory_not_reserved';
  end if;

  if p_status='cancelled' and exists(
    select 1 from public.inventory_movements im
    where im.order_id=p_order_id and im.movement_type='sale_reservation'
  ) then
    perform public.release_order_inventory(p_order_id);
    v_metadata:=coalesce(v_metadata,'{}'::jsonb)
      || jsonb_build_object('inventory_status','released');
  end if;

  update public.orders
  set status=p_status,delivery_status=coalesce(p_delivery_status,delivery_status),
      metadata=coalesce(v_metadata,metadata),updated_at=now()
  where id=p_order_id;
  return true;
end;
$function$;
