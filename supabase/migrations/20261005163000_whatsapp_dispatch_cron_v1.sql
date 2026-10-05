-- WhatsApp dispatcher guard + scheduled draining (Alfaeq Yemen).
--
-- * Skips work entirely while the WhatsApp Cloud API is unconfigured so queued
--   notifications are not marked failed before the owner adds the secrets.
-- * Adds an internal dispatcher that pg_cron can call as the postgres role.
-- * Schedules a per-minute drain when pg_cron is available.

-- ---------------------------------------------------------------------------
-- Configuration probe
-- ---------------------------------------------------------------------------
create or replace function private.whatsapp_configured()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, vault
as $$
  select exists (select 1 from vault.decrypted_secrets where name = 'WHATSAPP_ACCESS_TOKEN')
     and exists (select 1 from vault.decrypted_secrets where name = 'WHATSAPP_PHONE_NUMBER_ID')
$$;

revoke all on function private.whatsapp_configured() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Internal dispatcher (no auth check; callers are trusted)
-- ---------------------------------------------------------------------------
create or replace function private.whatsapp_dispatch_internal(p_limit integer default 10)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  r record;
  n integer := 0;
begin
  if not private.whatsapp_configured() then
    return 0;
  end if;

  for r in
    select to_jsonb(w) as row
      from public.whatsapp_notifications w
     where w.status in ('pending', 'failed')
       and w.attempts < 5
       and w.available_at <= now()
     order by w.created_at
     limit greatest(1, least(coalesce(p_limit, 10), 50))
  loop
    update public.whatsapp_notifications
       set attempts = attempts + 1,
           available_at = now() + (least(3600, power(2, attempts + 1) * 15)::text || ' seconds')::interval,
           updated_at = now()
     where id = r.row->>'id';
    perform private.whatsapp_send_row(r.row);
    n := n + 1;
  end loop;

  return n;
end;
$$;

revoke all on function private.whatsapp_dispatch_internal(integer) from public, anon, authenticated;

-- Public dispatcher now delegates and keeps its authorization check.
create or replace function public.whatsapp_dispatch(p_limit integer default 10)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if not (private.is_platform_staff() or auth.role() = 'service_role') then
    raise exception 'not_authorized';
  end if;
  return private.whatsapp_dispatch_internal(p_limit);
end;
$$;

revoke all on function public.whatsapp_dispatch(integer) from public, anon;
grant execute on function public.whatsapp_dispatch(integer) to authenticated, service_role;

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
      perform cron.unschedule('alfaeq-whatsapp-dispatch');
    exception when others then
      null;
    end;
    perform cron.schedule(
      'alfaeq-whatsapp-dispatch',
      '* * * * *',
      $cron$select private.whatsapp_dispatch_internal(20)$cron$
    );
  end if;
end;
$$;
