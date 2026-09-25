create or replace function public.claim_automation_events(
  p_limit integer default 20,
  p_worker_id text default 'automation-worker'
)
returns setof public.automation_events
language plpgsql
security definer
set search_path=''
as $$
begin
  if current_user <> 'service_role' then raise exception 'service_role_required'; end if;
  if p_limit is null or p_limit < 1 or p_limit > 50 then raise exception 'invalid_batch_size'; end if;

  update public.automation_events
     set status='pending', available_at=now(),
         last_error=coalesce(last_error,'stale processing lock')
   where status='processing'
     and available_at < now() - interval '10 minutes'
     and attempts < 10;

  return query
  with picked as (
    select e.id from public.automation_events e
     where e.status='pending' and e.available_at <= now() and e.attempts < 10
     order by e.id for update skip locked limit p_limit
  )
  update public.automation_events e
     set status='processing', attempts=e.attempts+1, last_error=null
    from picked where e.id=picked.id
  returning e.*;
end
$$;

create or replace function public.finish_automation_event(
  p_event_id bigint, p_success boolean, p_error text default null
)
returns boolean
language plpgsql security definer set search_path=''
as $$
declare v_attempts integer;
begin
  if current_user <> 'service_role' then raise exception 'service_role_required'; end if;
  select attempts into v_attempts from public.automation_events where id=p_event_id for update;
  if not found then return false; end if;

  if p_success then
    update public.automation_events set status='processed',processed_at=now(),last_error=null where id=p_event_id;
  elsif v_attempts >= 10 then
    update public.automation_events set status='failed',last_error=left(coalesce(p_error,'automation delivery failed'),2000) where id=p_event_id;
  else
    update public.automation_events
       set status='pending',
           available_at=now()+make_interval(secs=>least(3600,greatest(15,power(2::numeric,v_attempts)::integer*15))),
           last_error=left(coalesce(p_error,'automation delivery failed'),2000)
     where id=p_event_id;
  end if;
  return true;
end
$$;

revoke execute on function public.claim_automation_events(integer,text) from public,anon,authenticated;
revoke execute on function public.finish_automation_event(bigint,boolean,text) from public,anon,authenticated;
grant execute on function public.claim_automation_events(integer,text) to service_role;
grant execute on function public.finish_automation_event(bigint,boolean,text) to service_role;

create index if not exists automation_events_processing_idx
  on public.automation_events (status, available_at, id)
  where status in ('pending','processing');
