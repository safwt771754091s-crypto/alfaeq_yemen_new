create table if not exists public.automation_event_inbox (
  id uuid primary key default gen_random_uuid(),
  event_id text not null unique,
  source text not null default 'alfaeq_yemen_new',
  version integer not null default 1,
  event_type text not null,
  occurred_at timestamptz not null,
  data jsonb not null default '{}'::jsonb,
  received_at timestamptz not null default now(),
  status text not null default 'received' check (status in ('received','processing','processed','failed')),
  attempts integer not null default 0,
  last_error text,
  processed_at timestamptz
);
create index if not exists automation_event_inbox_type_idx on public.automation_event_inbox(event_type, received_at desc);
create index if not exists automation_event_inbox_status_idx on public.automation_event_inbox(status, received_at desc);
alter table public.automation_event_inbox enable row level security;
revoke all on public.automation_event_inbox from anon, authenticated;
comment on table public.automation_event_inbox is 'Idempotent inbox for Alfaeq automation events. One event_id is accepted once; business side effects remain in dedicated workflows.';
