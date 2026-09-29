-- Production Event Bus producers for Order -> Inventory -> Merchant.
-- Supabase remains the source of truth. This migration only emits durable automation events;
-- it does not mutate business state or expose privileged inventory operations to clients.

create or replace function public.emit_order_inventory_merchant_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event_type text;
  v_aggregate_type text;
  v_aggregate_id text;
  v_payload jsonb;
begin
  if tg_table_name = 'orders' then
    v_aggregate_type := 'order';
    v_aggregate_id := coalesce(new.id, old.id);

    if tg_op = 'INSERT' then
      v_event_type := 'order.created';
      v_payload := jsonb_build_object(
        'source','supabase',
        'table','orders',
        'operation','INSERT',
        'record',to_jsonb(new)
      );
    elsif
      old.status is distinct from new.status
      or old.delivery_status is distinct from new.delivery_status
      or old.merchant_id is distinct from new.merchant_id
      or old.merchant_ids is distinct from new.merchant_ids
    then
      v_event_type := 'order.status_changed';
      v_payload := jsonb_build_object(
        'source','supabase',
        'table','orders',
        'operation','UPDATE',
        'record',to_jsonb(new),
        'previous',to_jsonb(old),
        'status_before',old.status,
        'status_after',new.status,
        'delivery_status_before',old.delivery_status,
        'delivery_status_after',new.delivery_status
      );
    else
      return new;
    end if;

    insert into public.automation_events(event_type, aggregate_type, aggregate_id, payload)
    values (v_event_type, v_aggregate_type, v_aggregate_id, v_payload);
    return new;
  end if;

  if tg_table_name = 'inventory_movements' and tg_op = 'INSERT' then
    v_aggregate_type := 'inventory';
    v_aggregate_id := coalesce(new.product_id, new.id::text);

    v_event_type := case
      when new.movement_type in ('sale_reservation','reservation') then 'inventory.reserved'
      when new.movement_type in ('sale_release','reservation_release','release') then 'inventory.released'
      else 'inventory.adjusted'
    end;

    v_payload := jsonb_build_object(
      'source','supabase',
      'table','inventory_movements',
      'operation','INSERT',
      'record',to_jsonb(new),
      'order_id',new.order_id,
      'product_id',new.product_id,
      'movement_type',new.movement_type
    );

    insert into public.automation_events(event_type, aggregate_type, aggregate_id, payload)
    values (v_event_type, v_aggregate_type, v_aggregate_id, v_payload);
    return new;
  end if;

  if tg_table_name = 'stores' then
    v_aggregate_type := 'merchant';
    v_aggregate_id := coalesce(new.id, old.id);

    if tg_op = 'INSERT' then
      v_event_type := 'merchant.store.created';
      v_payload := jsonb_build_object(
        'source','supabase',
        'table','stores',
        'operation','INSERT',
        'record',to_jsonb(new)
      );
    elsif old.owner_id is distinct from new.owner_id
      or old.status is distinct from new.status
      or old.name is distinct from new.name
    then
      v_event_type := 'merchant.store.updated';
      v_payload := jsonb_build_object(
        'source','supabase',
        'table','stores',
        'operation','UPDATE',
        'record',to_jsonb(new),
        'previous',to_jsonb(old)
      );
    else
      return new;
    end if;

    insert into public.automation_events(event_type, aggregate_type, aggregate_id, payload)
    values (v_event_type, v_aggregate_type, v_aggregate_id, v_payload);
    return new;
  end if;

  return coalesce(new, old);
end;
$$;

revoke all on function public.emit_order_inventory_merchant_event() from public, anon, authenticated;

drop trigger if exists order_event_bus on public.orders;
create trigger order_event_bus
after insert or update on public.orders
for each row execute function public.emit_order_inventory_merchant_event();

drop trigger if exists inventory_event_bus on public.inventory_movements;
create trigger inventory_event_bus
after insert on public.inventory_movements
for each row execute function public.emit_order_inventory_merchant_event();

drop trigger if exists merchant_event_bus on public.stores;
create trigger merchant_event_bus
after insert or update on public.stores
for each row execute function public.emit_order_inventory_merchant_event();

comment on function public.emit_order_inventory_merchant_event() is
'Production Event Bus producer. Emits order, inventory and merchant domain events after committed business mutations. No client execute privilege.';
