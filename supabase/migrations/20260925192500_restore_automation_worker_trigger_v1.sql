create or replace function private.trigger_automation_worker()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  cfg public.automation_endpoints%rowtype;
  worker_url text := 'https://esvljorjykzgrpnrxnma.supabase.co/functions/v1/automation-worker';
begin
  select * into cfg
  from public.automation_endpoints
  where id='n8n' and enabled=true
  limit 1;

  if cfg.shared_secret is null or cfg.endpoint_url is null then
    return new;
  end if;

  perform net.http_post(
    url := worker_url,
    body := '{"limit":10}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'x-alfaeq-worker-secret',cfg.shared_secret
    ),
    timeout_milliseconds := 10000
  );

  return new;
exception when others then
  raise warning 'automation worker trigger failed: %', sqlerrm;
  return new;
end;
$function$;

drop trigger if exists automation_worker_dispatch on public.automation_events;

create trigger automation_worker_dispatch
after insert on public.automation_events
for each row
execute function private.trigger_automation_worker();

