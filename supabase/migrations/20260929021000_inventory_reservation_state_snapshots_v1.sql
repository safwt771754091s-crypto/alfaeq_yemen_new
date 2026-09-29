-- Extend inventory reservation with production state snapshots.
-- The product row remains the source of truth; the snapshot is compensation/audit metadata.
-- Critical stock mutation still uses SELECT ... FOR UPDATE and one transaction.

create or replace function public.reserve_order_inventory(p_order_id text)
returns table(product_id text, reserved_quantity numeric, stock_before numeric, stock_after numeric)
language plpgsql security definer set search_path = public
as $$
declare
  item record; p record; qty numeric; qty_base numeric;
  before_stock numeric; after_stock numeric; before_base numeric; after_base numeric;
  already_reserved boolean; snap record;
begin
  if current_user <> 'service_role' then raise exception 'service_role_required'; end if;
  if p_order_id is null or btrim(p_order_id) = '' then raise exception 'order_id is required'; end if;
  if not exists (select 1 from public.orders where id = p_order_id) then raise exception 'order not found: %', p_order_id; end if;

  for item in
    select oi.product_id, sum(oi.quantity) quantity,
           sum(coalesce(oi.quantity_base, oi.quantity)) quantity_base
    from public.order_items oi
    where oi.order_id = p_order_id and oi.product_id is not null
    group by oi.product_id order by oi.product_id
  loop
    select * into p from public.products where id = item.product_id for update;
    if not found then raise exception 'product not found: %', item.product_id; end if;

    qty := item.quantity; qty_base := item.quantity_base;
    if qty <= 0 or qty_base <= 0 then raise exception 'invalid quantity for product %', item.product_id; end if;

    select exists(
      select 1 from public.inventory_movements im
      where im.order_id=p_order_id and im.product_id=item.product_id
        and im.movement_type='sale_reservation'
    ) into already_reserved;

    if already_reserved then
      product_id:=item.product_id; reserved_quantity:=qty;
      stock_before:=p.stock; stock_after:=p.stock;
      return next; continue;
    end if;

    before_stock := p.stock;
    before_base := coalesce(p.stock_base,p.stock);
    after_stock := greatest(0,p.stock-qty);
    after_base := greatest(0,before_base-qty_base);

    select * into snap
    from public.begin_operation_snapshot(
      'inventory-reservation:' || p_order_id || ':' || item.product_id,
      'inventory_reservation', 'product', item.product_id,
      jsonb_build_object(
        'order_id', p_order_id, 'stock', before_stock,
        'stock_base', before_base,
        'sold_quantity', coalesce(p.sold_quantity,0),
        'sold_quantity_base', coalesce(p.sold_quantity_base,0)
      )
    );

    if not snap.acquired then
      if snap.status = 'completed' then
        product_id:=item.product_id; reserved_quantity:=qty;
        stock_before:=before_stock; stock_after:=before_stock;
        return next; continue;
      end if;
      raise exception 'inventory reservation snapshot already active for order %, product %',
        p_order_id, item.product_id;
    end if;

    if before_base < qty_base then
      raise exception 'insufficient stock for product %: requested %, available %',
        item.product_id, qty_base, before_base;
    end if;

    update public.products
       set stock=after_stock, stock_base=after_base,
           sold_quantity=coalesce(sold_quantity,0)+qty,
           sold_quantity_base=coalesce(sold_quantity_base,0)+qty_base,
           updated_at=now()
     where id=item.product_id;

    insert into public.inventory_movements(
      product_id, order_id, quantity, quantity_base,
      stock_before_base, stock_after_base, movement_type
    ) values (
      item.product_id, p_order_id, qty, qty_base,
      before_base, after_base, 'sale_reservation'
    );

    perform public.complete_operation_snapshot(
      snap.snapshot_id,
      jsonb_build_object(
        'order_id', p_order_id, 'stock', after_stock,
        'stock_base', after_base,
        'sold_quantity', coalesce(p.sold_quantity,0)+qty,
        'sold_quantity_base', coalesce(p.sold_quantity_base,0)+qty_base
      )
    );

    product_id:=item.product_id; reserved_quantity:=qty;
    stock_before:=before_stock; stock_after:=after_stock;
    return next;
  end loop;
end;
$$;

revoke all on function public.reserve_order_inventory(text) from public, anon, authenticated;
grant execute on function public.reserve_order_inventory(text) to service_role;

comment on function public.reserve_order_inventory(text) is
  'Atomically reserves order inventory with row locks, idempotent movements, state snapshots, and transactional compensation metadata.';
