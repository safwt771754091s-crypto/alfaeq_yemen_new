-- Alfaeq Yemen: idempotent reservation release hardening v5
create or replace function public.release_order_inventory(p_order_id text)
returns table(product_id text, released_quantity numeric, stock_before numeric, stock_after numeric)
language plpgsql
security definer
set search_path = public
as $function$
declare
  m record; p record; before_stock numeric; after_stock numeric;
begin
  if p_order_id is null or btrim(p_order_id)='' then
    raise exception 'order_id is required';
  end if;

  for m in
    select im.product_id,sum(im.quantity) quantity,sum(im.quantity_base) quantity_base
    from public.inventory_movements im
    where im.order_id=p_order_id
      and im.movement_type='sale_reservation'
      and not exists (
        select 1
        from public.inventory_movements r
        where r.order_id=p_order_id
          and r.product_id=im.product_id
          and r.movement_type='sale_reservation_release'
      )
    group by im.product_id
    order by im.product_id
  loop
    select * into p from public.products where id=m.product_id for update;
    if not found then
      raise exception 'product not found: %',m.product_id;
    end if;

    before_stock:=p.stock;
    after_stock:=coalesce(p.stock,0)+coalesce(m.quantity,0);

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

    product_id:=m.product_id;
    released_quantity:=m.quantity;
    stock_before:=before_stock;
    stock_after:=after_stock;
    return next;
  end loop;
end;
$function$;

revoke all on function public.release_order_inventory(text) from public,anon,authenticated;
grant execute on function public.release_order_inventory(text) to service_role;