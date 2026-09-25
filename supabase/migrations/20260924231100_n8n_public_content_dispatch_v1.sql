-- Store the n8n destination only in the private database. Never commit the webhook URL or secret.
create table if not exists public.automation_endpoints (
  id text primary key,
  endpoint_url text not null,
  shared_secret text not null,
  enabled boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.automation_endpoints enable row level security;

create or replace function public.dispatch_automation_event()
returns trigger language plpgsql security definer set search_path = public as $$
declare cfg public.automation_endpoints%rowtype; aggregate_id text; aggregate_type text; event_type text; payload jsonb;
begin
  select * into cfg from public.automation_endpoints where id='n8n' and enabled=true limit 1;
  if cfg.endpoint_url is null or cfg.shared_secret is null then return coalesce(new,old); end if;
  aggregate_id := coalesce(new.id,old.id);
  aggregate_type := case when tg_table_name='promotions' then 'promotion' else 'site_update' end;
  event_type := case when tg_op='INSERT' then aggregate_type||'.created' when tg_op='UPDATE' then aggregate_type||'.updated' else aggregate_type||'.deleted' end;
  payload := jsonb_build_object('source','alfaeq_yemen_new','version',1,'eventId',aggregate_type||':'||aggregate_id||':'||extract(epoch from clock_timestamp())::bigint,'eventType',event_type,'occurredAt',now(),'data',jsonb_build_object('id',aggregate_id,'record',to_jsonb(new),'previous',case when tg_op='UPDATE' then to_jsonb(old) else null end));
  perform net.http_post(url:=cfg.endpoint_url,body:=payload,headers:=jsonb_build_object('Content-Type','application/json','x-alfaeq-automation-secret',cfg.shared_secret),timeout_milliseconds:=10000);
  return coalesce(new,old);
exception when others then raise warning 'automation endpoint dispatch failed: %',sqlerrm; return coalesce(new,old);
end; $$;

drop trigger if exists promotions_n8n_dispatch on public.promotions;
create trigger promotions_n8n_dispatch after insert or update or delete on public.promotions for each row execute function public.dispatch_automation_event();

drop trigger if exists site_updates_n8n_dispatch on public.public_site_updates;
create trigger site_updates_n8n_dispatch after insert or update or delete on public.public_site_updates for each row execute function public.dispatch_automation_event();
