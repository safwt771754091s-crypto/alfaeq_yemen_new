-- Canonical automation inbox: recover events stranded in 'processing'.
--
-- automation-worker claims a row with `update ... set status='processing'`
-- before calling n8n. If the edge invocation dies mid-flight (timeout,
-- cold-start kill, redeploy) the row keeps status='processing' forever:
-- the worker only selects status='received', so the event is silently
-- dropped. The legacy automation_events queue self-heals via
-- claim_automation_events(); the canonical inbox had no equivalent path.
--
-- This migration adds an explicit claim timestamp, a reap function that
-- returns stale claims to the retry queue, and a self-healing scheduled
-- drain so the worker is re-invoked after retry backoff windows (the
-- insert trigger only fires once, at enqueue time).

-- ---------------------------------------------------------------------------
-- Claim timestamp (nullable so existing rows are reaped immediately)
-- ---------------------------------------------------------------------------
alter table public.automation_event_inbox
  add column if not exists processing_at timestamptz;

comment on column public.automation_event_inbox.processing_at is
'Set when automation-worker claims the row; used to detect and recover stale processing claims.';

-- ---------------------------------------------------------------------------
-- Reap stale processing claims back to 'received' for a bounded retry.
-- Returns the number of rows recovered.
-- ---------------------------------------------------------------------------
create or replace function public.reap_stale_automation_inbox(p_stale_seconds integer default 600)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_count integer;
begin
  if p_stale_seconds is null or p_stale_seconds < 60 then
    raise exception 'invalid_stale_window';
  end if;

  update public.automation_event_inbox
     set status = 'received',
         available_at = now(),
         processing_at = null,
         last_error = coalesce(last_error, 'stale processing claim recovered')
   where status = 'processing'
     and coalesce(processing_at, received_at) < now() - make_interval(secs => p_stale_seconds)
     and attempts < 10;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.reap_stale_automation_inbox(integer) from public, anon, authenticated;
grant execute on function public.reap_stale_automation_inbox(integer) to service_role;

comment on function public.reap_stale_automation_inbox(integer) is
'Returns stale processing claims in automation_event_inbox to the received state so a crashed worker delivery is retried instead of dropped.';

-- ---------------------------------------------------------------------------
-- Internal dispatcher + self-healing scheduled drain.
-- Reaps stale claims, then re-invokes automation-worker so retried rows are
-- picked up after their available_at backoff window elapses.
-- ---------------------------------------------------------------------------
create or replace function private.automation_inbox_drain_internal(p_limit integer default 10)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  cfg public.automation_endpoints%rowtype;
  worker_url text := 'https://esvljorjykzgrpnrxnma.supabase.co/functions/v1/automation-worker';
  v_stale integer;
  v_pending integer;
begin
  v_stale := public.reap_stale_automation_inbox(600);

  select count(*) into v_pending
    from public.automation_event_inbox
   where status = 'received'
     and available_at <= now()
     and attempts < 10;

  if v_pending = 0 then
    return v_stale;
  end if;

  select * into cfg
    from public.automation_endpoints
   where id = 'n8n' and enabled = true
   limit 1;

  if cfg.shared_secret is null then
    return v_stale;
  end if;

  perform net.http_post(
    url := worker_url,
    body := jsonb_build_object('limit', greatest(1, least(coalesce(p_limit, 10), 10))),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-alfaeq-worker-secret', cfg.shared_secret
    ),
    timeout_milliseconds := 10000
  );

  return v_stale + v_pending;
exception when others then
  raise warning 'automation inbox drain failed: %', sqlerrm;
  return v_stale;
end;
$$;

revoke all on function private.automation_inbox_drain_internal(integer) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Scheduled draining (best effort; no-op when pg_cron is unavailable)
-- ---------------------------------------------------------------------------
do $$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    raise notice 'pg_cron unavailable: %', sqlerrm;
  end;

  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      perform cron.unschedule('alfaeq-automation-inbox-drain');
    exception when others then
      null;
    end;
    perform cron.schedule(
      'alfaeq-automation-inbox-drain',
      '* * * * *',
      $cron$select private.automation_inbox_drain_internal(10)$cron$
    );
  end if;
end;
$$;
