-- Production hardening for the Alfaeq Yemen automation/data plane.
-- Safe/idempotent: no user data is deleted or rewritten.

drop trigger if exists login_events_email_webhook on public.login_events;

create index if not exists automation_events_ready_idx
  on public.automation_events (status, available_at, created_at);
create index if not exists automation_events_aggregate_idx
  on public.automation_events (aggregate_type, aggregate_id, created_at desc);
create index if not exists automation_jobs_ready_idx
  on public.automation_jobs (status, run_after, priority desc, created_at);
create index if not exists notifications_user_unread_idx
  on public.notifications (user_id, created_at desc)
  where read_at is null;
create index if not exists login_events_uid_time_idx
  on public.login_events (uid, login_at desc);
create index if not exists orders_customer_time_idx
  on public.orders (customer_id, created_at desc);
create index if not exists orders_driver_status_idx
  on public.orders (driver_id, delivery_status, updated_at desc);
create index if not exists products_store_status_idx
  on public.products (store_id, status, updated_at desc);
create index if not exists inventory_movements_product_time_idx
  on public.inventory_movements (product_id, created_at desc);
