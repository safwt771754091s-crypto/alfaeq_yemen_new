alter table public.automation_event_inbox
  add column if not exists available_at timestamptz not null default now();

create index if not exists automation_event_inbox_available_idx
  on public.automation_event_inbox(status, available_at, received_at)
  where status in ('received','processing');
