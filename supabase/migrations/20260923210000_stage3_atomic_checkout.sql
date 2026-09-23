-- Stage 3: make Supabase checkout consume the customer's cart atomically.
-- Pricing, stock validation, order creation and cart clearing stay in one transaction.
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
    payment_method, total, currency, items
  )
  values(
    v_order_id, v_customer_id, 'pending', 'awaiting_assignment',
    nullif(trim(p_address), ''), p_latitude, p_longitude,
    nullif(trim(p_payment_method), ''), 0, 'YER', p_items
  );

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_qty := nullif(v_item->>'quantity','')::numeric;
    if v_qty is null or v_qty <= 0 then
      raise exception 'invalid_quantity' using errcode='22023';
    end if;

    select * into v_product
    from public.products
    where id = v_item->>'product_id' and status = 'active'
    for update;

    if not found then
      raise exception 'product_not_available:%', v_item->>'product_id' using errcode='P0001';
    end if;
    if v_product.stock < v_qty then
      raise exception 'insufficient_stock:%', v_product.id using errcode='P0001';
    end if;

    if v_currency is null then
      v_currency := coalesce(v_product.currency, 'YER');
    elsif v_product.currency <> v_currency then
      raise exception 'mixed_currencies_not_supported' using errcode='22023';
    end if;

    select s.owner_id into v_store_owner
    from public.stores s
    where s.id = v_product.store_id;

    if v_store_owner is not null and not (v_store_owner = any(v_merchant_ids)) then
      v_merchant_ids := array_append(v_merchant_ids, v_store_owner);
    end if;

    v_line_total := v_product.price * v_qty;
    v_total := v_total + v_line_total;

    insert into public.order_items(
      order_id, product_id, store_id, name, quantity, quantity_base,
      unit_price, currency, metadata
    )
    values(
      v_order_id, v_product.id, v_product.store_id, v_product.name, v_qty,
      coalesce(v_qty * v_product.unit_scale, v_qty),
      v_product.price, v_product.currency,
      jsonb_build_object('source','server_priced')
    );

    update public.products
    set stock = stock - v_qty,
        sold_quantity = sold_quantity + v_qty,
        sold_quantity_base = sold_quantity_base + coalesce(v_qty * unit_scale, v_qty),
        updated_at = now()
    where id = v_product.id;
  end loop;

  update public.orders
  set total = v_total,
      currency = coalesce(v_currency, 'YER'),
      merchant_ids = v_merchant_ids,
      merchant_id = case when cardinality(v_merchant_ids) = 1 then v_merchant_ids[1] else null end,
      updated_at = now()
  where id = v_order_id;

  -- The order and the cart are consumed atomically. If any validation above
  -- fails, PostgreSQL rolls the entire transaction back and the cart remains.
  update public.carts
  set items = '[]'::jsonb,
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('last_order_id', v_order_id),
      updated_at = now()
  where uid = v_customer_id;

  return v_order_id;
end;
$function$;

revoke execute on function private.create_order_internal(jsonb,text,text,double precision,double precision) from public, anon, authenticated;
