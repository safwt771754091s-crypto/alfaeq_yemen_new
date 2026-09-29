-- Production Event Bus producer for inventory.
-- Orders and stores already use the existing private enqueue_automation_event outbox.
-- This migration adds only the missing inventory producer to avoid duplicate events.

create or replace function private.trg_enqueue_inventory_event()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_event_type text;
begin
  v_event_type := case
    when new.movement_type in ('sale_reservation','reservation') then 'inventory.reserved'
    when new.movement_type in ('sale_release','reservation_release','release') then 'inventory.released'
    else 'inventory.adjusted'
  end;

  perform private.enqueue_automation_event(
    v_event_type,
    'inventory',
    new.product_id,
    jsonb_build_object(
      'source','supabase',
      'table','inventory_movements',
      'operation','INSERT',
      'record',to_jsonb(new),
      'order_id',new.order_id,
      'product_id',new.product_id,
      'movement_type',new.movement_type
    )
  );

  return new;
end;
$$;

revoke all on function private.trg_enqueue_inventory_event() from public, anon, authenticated;

drop trigger if exists automation_inventory_outbox on public.inventory_movements;
create trigger automation_inventory_outbox
after insert on public.inventory_movements
for each row execute function private.trg_enqueue_inventory_event();

comment on function private.trg_enqueue_inventory_event() is
'Emits inventory domain events through the existing private automation outbox. Clients have no execute privilege.';
