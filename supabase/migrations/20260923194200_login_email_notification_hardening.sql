-- Production login/register email notifications.
-- The webhook secret is generated in the database and is never committed.

create extension if not exists pg_net;

create table if not exists public.notification_webhook_secrets (
  id text primary key,
  secret text not null,
  created_at timestamptz not null default now()
);

alter table public.notification_webhook_secrets enable row level security;
revoke all on table public.notification_webhook_secrets from anon, authenticated;
grant select on table public.notification_webhook_secrets to service_role;

insert into public.notification_webhook_secrets (id, secret)
values ('login_events', encode(gen_random_bytes(32), 'hex'))
on conflict (id) do nothing;

create or replace function public.enqueue_login_event_email()
returns trigger
language plpgsql
security definer
set search_path = public, net, pg_temp
as $$
declare
  webhook_secret text;
begin
  select secret
    into webhook_secret
  from public.notification_webhook_secrets
  where id = 'login_events';

  if webhook_secret is null then
    raise warning 'login event email webhook secret is missing';
    return new;
  end if;

  perform net.http_post(
    url := 'https://esvljorjykzgrpnrxnma.supabase.co/functions/v1/notify-login-event',
    body := jsonb_build_object(
      'type', 'INSERT',
      'table', 'login_events',
      'schema', 'public',
      'record', to_jsonb(new),
      'old_record', null
    ),
    params := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Webhook-Secret', webhook_secret
    ),
    timeout_milliseconds := 10000
  );

  return new;
end;
$$;

revoke execute on function public.enqueue_login_event_email() from anon, authenticated;
grant execute on function public.enqueue_login_event_email() to service_role;

drop trigger if exists login_events_email_webhook on public.login_events;
create trigger login_events_email_webhook
after insert on public.login_events
for each row
execute function public.enqueue_login_event_email();

create index if not exists chat_messages_thread_id_idx
  on public.chat_messages (thread_id);

create index if not exists wallet_ledger_wallet_uid_idx
  on public.wallet_ledger (wallet_uid);
