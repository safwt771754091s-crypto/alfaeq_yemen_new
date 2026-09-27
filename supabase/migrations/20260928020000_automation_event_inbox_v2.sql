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

create or replace function public.accept_automation_event(
  p_event_id text,
  p_source text,
  p_version integer,
  p_event_type text,
  p_occurred_at timestamptz,
  p_data jsonb
) returns table(accepted boolean, duplicate boolean)
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.automation_event_inbox(event_id,source,version,event_type,occurred_at,data)
  values (p_event_id,p_source,p_version,p_event_type,p_occurred_at,coalesce(p_data,'{}'::jsonb))
  on conflict (event_id) do nothing;
  if found then
    return query select true, false;
  else
    return query select false, true;
  end if;
end;
$$;
revoke all on function public.accept_automation_event(text,text,integer,text,timestamptz,jsonb) from public, anon, authenticated;
