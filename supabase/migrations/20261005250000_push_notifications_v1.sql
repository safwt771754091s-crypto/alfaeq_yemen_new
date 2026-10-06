-- Push notification infrastructure.
--
-- Every row inserted into public.notifications (order updates, chat messages,
-- moments, ...) is fanned out to the user's registered devices through the
-- `push-dispatch` edge function. The dispatch is fire-and-forget via pg_net,
-- so a failing/absent push provider never blocks the business transaction.

-- One row per device per user. Tokens are unique; re-registering refreshes
-- ownership/last_seen so a reinstalled app reuses its row.
create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  token text not null unique,
  platform text not null default 'unknown',
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create index if not exists device_tokens_user_idx on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

drop policy if exists device_tokens_owner_all on public.device_tokens;
create policy device_tokens_owner_all on public.device_tokens
  for all to authenticated
  using (user_id = current_user_uid())
  with check (user_id = current_user_uid());

-- Client RPC: register/refresh the calling user's device token.
create or replace function public.register_device_token(p_token text, p_platform text default 'unknown')
returns void
language plpgsql
security definer
set search_path to 'pg_catalog','public','auth'
as $function$
declare
  v_uid text := auth.uid()::text;
begin
  if v_uid is null then
    raise exception 'authentication_required';
  end if;
  if p_token is null or length(btrim(p_token)) < 10 then
    raise exception 'invalid_device_token';
  end if;
  insert into public.device_tokens(user_id, token, platform, last_seen_at)
  values (v_uid, btrim(p_token), coalesce(nullif(btrim(p_platform),''),'unknown'), now())
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        last_seen_at = now();
end
$function$;

revoke all on function public.register_device_token(text, text) from public, anon;
grant execute on function public.register_device_token(text, text) to authenticated;

-- Dispatch configuration (shared secret + function URL) lives in the private
-- schema, which is not exposed through PostgREST.
create table if not exists private.push_dispatch_config (
  base_url text,
  secret text
);

-- Fan out each new notification to the push-dispatch edge function.
create or replace function private.trg_push_notification()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_secret text;
  v_url text;
  v_body jsonb;
begin
  select secret, base_url into v_secret, v_url from private.push_dispatch_config limit 1;
  if v_secret is null or v_url is null then
    return new;
  end if;

  v_body := jsonb_build_object(
    'userId', new.user_id,
    'notificationId', new.id,
    'type', new.type,
    'title', new.title,
    'body', new.body,
    'data', coalesce(new.data, '{}'::jsonb)
  );

  perform net.http_post(
    url := v_url,
    body := v_body,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-alfaeq-signature', encode(extensions.hmac(v_body::text, v_secret, 'sha256'), 'hex')
    ),
    timeout_milliseconds := 5000
  );

  return new;
end
$function$;

drop trigger if exists push_on_notification on public.notifications;
create trigger push_on_notification
  after insert on public.notifications
  for each row execute function private.trg_push_notification();
