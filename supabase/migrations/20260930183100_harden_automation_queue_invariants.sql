-- Harden automation queue invariants and retry observability.
-- Applied live on 2026-09-30 and recorded here as the authoritative migration history.

do $$
begin
  alter table public.automation_event_inbox
    add constraint automation_event_inbox_status_ck
    check (status in ('received','processing','processed','failed'));
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table public.automation_event_inbox
    add constraint automation_event_inbox_attempts_ck
    check (attempts >= 0 and attempts <= 10);
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table public.automation_event_inbox
    add constraint automation_event_inbox_version_ck
    check (version >= 1);
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table public.automation_events
    add constraint automation_events_status_ck
    check (status in ('pending','processing','processed','failed'));
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table public.automation_events
    add constraint automation_events_attempts_ck
    check (attempts >= 0 and attempts <= 10);
exception when duplicate_object then null;
end $$;

create index if not exists automation_event_inbox_retry_idx
  on public.automation_event_inbox (status, attempts, received_at)
  where status in ('received','processing');

create index if not exists automation_events_failed_idx
  on public.automation_events (created_at desc, attempts)
  where status = 'failed';
