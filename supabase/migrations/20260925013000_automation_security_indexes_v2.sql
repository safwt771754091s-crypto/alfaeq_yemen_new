-- Harden trigger-only automation functions and remove duplicate indexes.
revoke execute on function public.dispatch_automation_event() from public, anon, authenticated;
revoke execute on function public.enqueue_content_automation() from public, anon, authenticated;

create index if not exists promotions_store_status_idx
  on public.promotions (store_id, status);

drop index if exists public.automation_events_ready_idx;
drop index if exists public.inventory_movements_product_time_idx2;
drop index if exists public.orders_customer_created_idx;
drop index if exists public.wallet_transactions_uid_time_idx;

create index if not exists automation_events_pending_idx
  on public.automation_events (status, created_at)
  where status = 'pending';

create index if not exists inventory_movements_product_time_idx
  on public.inventory_movements (product_id, created_at desc);

create index if not exists orders_customer_time_idx
  on public.orders (customer_id, created_at desc);

create index if not exists wallet_transactions_uid_time_idx
  on public.wallet_transactions (uid, created_at desc);
