-- Production outbox boundary for order.created.
-- The order mutation and its automation event are committed in the same transaction.
create or replace function private.enqueue_order_created_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.automation_event_inbox (
    event_id, source, version, event_type, occurred_at, data
  )
  values (
    'order.created:' || new.id::text || ':v1',
    'alfaeq_yemen_new',
    1,
    'order.created',
    coalesce(new.created_at, now()),
    jsonb_build_object(
      'aggregateId', new.id,
      'customerId', new.customer_id,
      'paymentMethod', new.payment_method,
      'status', new.status
    )
  )
  on conflict (event_id) do nothing;
  return new;
end;
$$;

drop trigger if exists orders_automation_event on public.orders;
create trigger orders_automation_event
after insert on public.orders
for each row execute function private.enqueue_order_created_event();

revoke execute on function private.enqueue_order_created_event() from public, anon, authenticated;
