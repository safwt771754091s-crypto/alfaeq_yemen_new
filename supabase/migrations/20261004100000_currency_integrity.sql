-- Currency integrity for checkout.
--
-- Bug: private.create_order_internal hardcoded orders.currency = 'YER' and never
-- took the currency from the products, so every USD order (99% of the catalog)
-- was recorded as YER. public.create_order_paid then preferred the client's
-- wallet currency over the order currency, so a YER wallet could "pay" a USD
-- order at a 1:1 rate.
--
-- Fix:
--   * create_order_internal derives the order currency from its items and
--     rejects carts that mix currencies (no FX conversion exists).
--   * create_order_paid debits in the ORDER currency and rejects a mismatching
--     client currency, so a wallet can only pay orders in its own currency.

create or replace function private.create_order_internal(
  p_items jsonb,
  p_address text,
  p_payment_method text,
  p_latitude double precision default null,
  p_longitude double precision default null
) returns text
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid text := auth.uid()::text;
  v_id text;
  v_total numeric := 0;
  v_currency text;
  item jsonb;
  v_product public.products%rowtype;
  v_qty numeric;
  v_qty_base numeric;
  v_item_currency text;
  v_merchant_ids text[] := '{}';
begin
  if v_uid is null then raise exception 'authentication_required'; end if;
  if jsonb_typeof(coalesce(p_items,'[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_items,'[]'::jsonb)) = 0 then
    raise exception 'items_must_be_non_empty_array';
  end if;

  v_id := 'ord_' || replace(gen_random_uuid()::text,'-','');

  insert into public.orders(
    id,customer_id,address,latitude,longitude,payment_method,status,
    delivery_status,total,currency,items,metadata
  )
  values(
    v_id,v_uid,p_address,p_latitude,p_longitude,p_payment_method,'pending',
    'pending',0,'YER',coalesce(p_items,'[]'::jsonb),'{}'
  );

  for item in select * from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    select * into v_product
    from public.products
    where id = coalesce(item->>'product_id',item->>'id')
      and status in ('active','published')
    for update;

    if not found then raise exception 'product_not_found'; end if;

    v_qty := coalesce((item->>'quantity')::numeric,0);
    if v_qty <= 0 then raise exception 'invalid_quantity'; end if;

    v_qty_base := coalesce((item->>'quantity_base')::numeric,v_qty);
    if v_qty_base <= 0 then raise exception 'invalid_quantity_base'; end if;

    v_item_currency := upper(coalesce(v_product.currency, 'YER'));
    if v_currency is null then
      v_currency := v_item_currency;
    elsif v_item_currency <> v_currency then
      raise exception 'mixed_currency_not_supported';
    end if;

    v_total := v_total + (v_product.price * v_qty);

    if not (v_product.store_id = any(v_merchant_ids)) then
      v_merchant_ids := array_append(v_merchant_ids, v_product.store_id);
    end if;

    insert into public.order_items(
      order_id,product_id,store_id,name,quantity,quantity_base,
      unit_price,currency,metadata
    )
    values(
      v_id,v_product.id,v_product.store_id,v_product.name,v_qty,v_qty_base,
      v_product.price,v_product.currency,item
    );
  end loop;

  update public.orders
  set merchant_ids=v_merchant_ids,
      total=v_total,
      currency=coalesce(v_currency,'YER'),
      updated_at=now()
  where id=v_id;

  perform 1 from public.reserve_order_inventory(v_id) limit 1;

  delete from public.carts where uid = v_uid;

  return v_id;
end
$function$;

create or replace function public.create_order_paid(
  p_items jsonb,
  p_address text,
  p_idempotency_key text,
  p_currency text default 'YER'::text,
  p_latitude double precision default null,
  p_longitude double precision default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid text := auth.uid()::text;
  v_id text;
  v_existing text;
  v_total numeric;
  v_curr text;
begin
  if v_uid is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if p_idempotency_key is null or length(btrim(p_idempotency_key)) < 8 then
    raise exception 'invalid_idempotency_key';
  end if;

  select id into v_existing
  from public.orders
  where customer_id = v_uid and metadata ->> 'checkout_key' = p_idempotency_key
  limit 1;
  if v_existing is not null then
    return v_existing;
  end if;

  begin
    v_id := private.create_order_internal(p_items, p_address, 'wallet', p_latitude, p_longitude);

    select total, currency into v_total, v_curr from public.orders where id = v_id;
    if v_total is null or v_total <= 0 then
      raise exception 'invalid_order_total';
    end if;

    -- The order currency is authoritative; the wallet must match it.
    if p_currency is not null and btrim(p_currency) <> ''
       and upper(btrim(p_currency)) <> upper(v_curr) then
      raise exception 'currency_mismatch';
    end if;

    perform private.wallet_debit_internal(v_total, v_curr, p_idempotency_key, 'order', v_id);

    update public.orders
    set payment_method = 'wallet',
        metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
          'payment_status', 'paid',
          'paid_at', now(),
          'checkout_key', p_idempotency_key,
          'wallet_currency', v_curr,
          'wallet_amount', v_total
        )
    where id = v_id;

    return v_id;
  exception when others then
    raise;
  end;
end
$function$;
