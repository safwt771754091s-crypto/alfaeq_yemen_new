-- Catalog pricing currency correction.
--
-- The imported catalog (993 rows from
-- "الفائق_يمن_منتجات_سوبر_الفائق_جاهز_للمراجعة.xlsx") stores Saudi retail prices
-- but was labelled `currency='USD'`. Because USD is the platform base, every
-- price was then re-converted with the full rate stack (SAR 3.75 x YER/SAR 410),
-- showing YER prices 3.75x too high (e.g. 8.85 -> 13606 YER instead of 3628).
--
-- Fixes:
--   1) Convert the mislabelled catalog rows to their true SAR price
--      (price_sar = price_usd_label * 3.75) and currency='SAR', once.
--   2) Make order pricing currency-aware: `create_order_internal` and
--      `create_order_paid` must convert from the product's own currency, not
--      assume USD.

-- 1) Correct the imported catalog (idempotent via metadata flag) ------------
update public.products
set price = round(price * coalesce((public.get_fx_rates() -> 'rates' ->> 'SAR')::numeric, 3.75), 2),
    currency = 'SAR',
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'price_currency_corrected', true,
      'price_currency_corrected_from', 'USD',
      'price_currency_corrected_at', now()
    ),
    updated_at = now()
where currency = 'USD'
  and metadata ->> 'source' like '%سوبر_الفائق%'
  and coalesce((metadata ->> 'price_currency_corrected')::boolean, false) = false;

-- 2) create_order_internal: convert from the product currency ---------------
create or replace function private.create_order_internal(
  p_items jsonb,
  p_address text,
  p_payment_method text default 'cash_on_delivery',
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_display_currency text default 'YER'
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
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
  v_disp text := upper(coalesce(nullif(btrim(p_display_currency),''),'YER'));
  v_disp_unit numeric;
begin
  if v_uid is null then raise exception 'authentication_required'; end if;
  if jsonb_typeof(coalesce(p_items,'[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_items,'[]'::jsonb)) = 0 then
    raise exception 'items_must_be_non_empty_array';
  end if;

  v_id := 'ord_' || replace(gen_random_uuid()::text,'-','');

  insert into public.orders(
    id,customer_id,address,latitude,longitude,payment_method,status,
    delivery_status,total,currency,items,metadata,display_currency
  )
  values(
    v_id,v_uid,p_address,p_latitude,p_longitude,p_payment_method,'pending',
    'pending',0,'USD',coalesce(p_items,'[]'::jsonb),'{}',v_disp
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

    v_item_currency := upper(coalesce(v_product.currency, 'USD'));
    if v_currency is null then
      v_currency := v_item_currency;
    elsif v_item_currency <> v_currency then
      raise exception 'mixed_currency_not_supported';
    end if;

    v_total := v_total + (v_product.price * v_qty);
    v_disp_unit := private.fx_convert(v_product.price, v_item_currency, v_disp);

    if not (v_product.store_id = any(v_merchant_ids)) then
      v_merchant_ids := array_append(v_merchant_ids, v_product.store_id);
    end if;

    insert into public.order_items(
      order_id,product_id,store_id,name,quantity,quantity_base,
      unit_price,currency,metadata,display_currency,display_unit_price
    )
    values(
      v_id,v_product.id,v_product.store_id,v_product.name,v_qty,v_qty_base,
      v_product.price,v_product.currency,item,v_disp,v_disp_unit
    );
  end loop;

  update public.orders
  set merchant_ids=v_merchant_ids,
      total=v_total,
      currency=coalesce(v_currency,'USD'),
      display_total=private.fx_convert(v_total, coalesce(v_currency,'USD'), v_disp),
      display_currency=v_disp,
      updated_at=now()
  where id=v_id;

  perform 1 from public.reserve_order_inventory(v_id) limit 1;

  delete from public.carts where uid = v_uid;

  return v_id;
end;
$function$;

-- 3) create_order_paid: convert order currency -> wallet currency -----------
create or replace function public.create_order_paid(
  p_items jsonb,
  p_address text,
  p_idempotency_key text,
  p_currency text default 'USD',
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_display_currency text default 'YER'
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $function$
declare
  v_uid text := auth.uid()::text;
  v_id text;
  v_existing text;
  v_total numeric;
  v_curr text;
  v_wallet public.wallets%rowtype;
  v_wallet_curr text;
  v_pay_total numeric;
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

  v_id := private.create_order_internal(p_items, p_address, 'wallet', p_latitude, p_longitude, p_display_currency);

  select total, currency into v_total, v_curr from public.orders where id = v_id;
  if v_total is null or v_total <= 0 then
    raise exception 'invalid_order_total';
  end if;
  v_curr := upper(coalesce(v_curr, 'USD'));

  -- The wallet's own currency is authoritative; the order total is converted to it.
  select * into v_wallet from public.wallets where uid = v_uid for update;
  if v_wallet.uid is null then
    v_wallet_curr := upper(coalesce(nullif(btrim(p_currency),''),'YER'));
    insert into public.wallets(uid, currency, status, available_balance, metadata, version, owner_uid, account_type)
    values (v_uid, v_wallet_curr, 'active', 0, '{}'::jsonb, 0, v_uid, 'customer')
    returning * into v_wallet;
    v_wallet_curr := v_wallet.currency;
  else
    v_wallet_curr := upper(v_wallet.currency);
  end if;

  if v_wallet_curr <> v_curr then
    v_pay_total := private.fx_convert(v_total, v_curr, v_wallet_curr);
  else
    v_pay_total := v_total;
  end if;

  perform private.wallet_debit_internal(v_pay_total, v_wallet_curr, p_idempotency_key, 'order', v_id);

  update public.orders
  set payment_method = 'wallet',
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'payment_status', 'paid',
        'paid_at', now(),
        'checkout_key', p_idempotency_key,
        'wallet_currency', v_wallet_curr,
        'wallet_amount', v_pay_total,
        'order_currency', v_curr,
        'order_amount', v_total
      )
  where id = v_id;

  return v_id;
end;
$function$;
