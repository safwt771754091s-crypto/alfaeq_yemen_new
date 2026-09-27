create unique index if not exists inventory_movements_order_product_reservation_uq on public.inventory_movements(order_id, product_id, movement_type) where order_id is not null and movement_type = 'sale_reservation';

create or replace function public.reserve_order_inventory(p_order_id text)
returns table(product_id text, reserved_quantity numeric, stock_before numeric, stock_after numeric)
language plpgsql security definer set search_path = public
as $$
declare item record; p record; qty numeric; qty_base numeric; before_stock numeric; after_stock numeric; already_reserved boolean;
begin
  if p_order_id is null or btrim(p_order_id) = '' then raise exception 'order_id is required'; end if;
  if not exists (select 1 from public.orders where id = p_order_id) then raise exception 'order not found: %', p_order_id; end if;
  for item in
    select oi.product_id, sum(oi.quantity) quantity, sum(coalesce(oi.quantity_base, oi.quantity)) quantity_base
    from public.order_items oi where oi.order_id = p_order_id and oi.product_id is not null group by oi.product_id order by oi.product_id
  loop
    select * into p from public.products where id = item.product_id for update;
    if not found then raise exception 'product not found: %', item.product_id; end if;
    qty := item.quantity; qty_base := item.quantity_base;
    if qty <= 0 or qty_base <= 0 then raise exception 'invalid quantity for product %', item.product_id; end if;
    select exists(select 1 from public.inventory_movements im where im.order_id=p_order_id and im.product_id=item.product_id and im.movement_type='sale_reservation') into already_reserved;
    if already_reserved then
      product_id:=item.product_id; reserved_quantity:=qty; stock_before:=p.stock; stock_after:=p.stock; return next; continue;
    end if;
    if coalesce(p.stock_base,p.stock) < qty_base then raise exception 'insufficient stock for product %: requested %, available %',item.product_id,qty_base,coalesce(p.stock_base,p.stock); end if;
    before_stock:=p.stock; after_stock:=greatest(0,p.stock-qty);
    update public.products set stock=after_stock, stock_base=greatest(0,coalesce(stock_base,stock)-qty_base), sold_quantity=coalesce(sold_quantity,0)+qty, sold_quantity_base=coalesce(sold_quantity_base,0)+qty_base, updated_at=now() where id=item.product_id;
    insert into public.inventory_movements(product_id,order_id,quantity,quantity_base,stock_before_base,stock_after_base,movement_type)
    values(item.product_id,p_order_id,qty,qty_base,coalesce(p.stock_base,p.stock),greatest(0,coalesce(p.stock_base,p.stock)-qty_base),'sale_reservation');
    product_id:=item.product_id; reserved_quantity:=qty; stock_before:=before_stock; stock_after:=after_stock; return next;
  end loop;
end; $$;
revoke all on function public.reserve_order_inventory(text) from public, anon, authenticated;
grant execute on function public.reserve_order_inventory(text) to service_role;
comment on function public.reserve_order_inventory(text) is 'Atomically reserves order inventory with row locks, idempotent sale_reservation movements, and rollback on any stock failure. Intended for trusted server-side order processing.';