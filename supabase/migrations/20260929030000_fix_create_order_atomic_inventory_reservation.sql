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
  item jsonb;
  v_product public.products%rowtype;
  v_qty numeric;
  v_qty_base numeric;
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
  set merchant_ids=v_merchant_ids,total=v_total,updated_at=now()
  where id=v_id;

  perform 1 from public.reserve_order_inventory(v_id) limit 1;

  return v_id;
end
$function$;