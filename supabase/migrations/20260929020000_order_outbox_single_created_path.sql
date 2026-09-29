-- order.created is delivered through the durable automation inbox.
-- Keep the legacy automation queue for order.updated only.
drop trigger if exists automation_order_outbox on public.orders;

create or replace function private.trg_enqueue_order_update_event()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  perform private.enqueue_automation_event(
    'order.updated',
    'order',
    new.id,
    to_jsonb(new)
  );
  return new;
end;
$$;

drop trigger if exists automation_order_update_outbox on public.orders;
create trigger automation_order_update_outbox
after update on public.orders
for each row execute function private.trg_enqueue_order_update_event();

revoke execute on function private.trg_enqueue_order_update_event() from public, anon, authenticated;
