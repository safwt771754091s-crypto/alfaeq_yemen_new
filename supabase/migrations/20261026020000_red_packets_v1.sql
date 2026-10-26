-- WeChat-style red packets (حزمة حمراء / 红包) in chat.
--
-- A sender locks a random or equal amount from their wallet and shares the
-- packet into a chat thread. Thread members open it and receive a random share;
-- the sender reclaims whatever is left after 24h. Money is only moved between
-- real wallets (no minting) and every leg is written to wallet_ledger under a
-- deterministic idempotency key, so retries can never double-pay.

create table if not exists public.red_packets (
  id uuid primary key default gen_random_uuid(),
  sender_uid text not null,
  thread_id uuid not null references public.chat_threads(id) on delete cascade,
  total_amount numeric not null check (total_amount > 0),
  remaining_amount numeric not null check (remaining_amount >= 0),
  share_count integer not null check (share_count between 1 and 100),
  opened_count integer not null default 0,
  currency text not null,
  packet_type text not null default 'random' check (packet_type in ('random','equal')),
  wish text,
  status text not null default 'open' check (status in ('open','finished','expired','reclaimed')),
  expires_at timestamptz not null default (now() + interval '24 hours'),
  created_at timestamptz not null default now(),
  finished_at timestamptz
);

create table if not exists public.red_packet_claims (
  id uuid primary key default gen_random_uuid(),
  packet_id uuid not null references public.red_packets(id) on delete cascade,
  uid text not null,
  amount numeric not null check (amount >= 0),
  created_at timestamptz not null default now(),
  unique (packet_id, uid)
);

create index if not exists red_packets_thread_idx on public.red_packets(thread_id, created_at desc);
create index if not exists red_packets_sender_idx on public.red_packets(sender_uid, created_at desc);
create index if not exists red_packet_claims_packet_idx on public.red_packet_claims(packet_id);
create index if not exists red_packet_claims_uid_idx on public.red_packet_claims(uid, created_at desc);

alter table public.red_packets enable row level security;
alter table public.red_packet_claims enable row level security;

-- Thread members (and staff) may see packets shared in their threads. Writes
-- only happen through the SECURITY DEFINER RPCs below.
drop policy if exists red_packets_select on public.red_packets;
create policy red_packets_select on public.red_packets
for select to authenticated
using (private.is_thread_member(thread_id) or private.is_platform_staff());

drop policy if exists red_packet_claims_select on public.red_packet_claims;
create policy red_packet_claims_select on public.red_packet_claims
for select to authenticated
using (
  uid = (select auth.uid())::text
  or exists (
    select 1 from public.red_packets p
    where p.id = red_packet_claims.packet_id
      and (private.is_thread_member(p.thread_id) or private.is_platform_staff())
  )
);

-- Best-effort Realtime for live "someone opened the packet" updates.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      alter publication supabase_realtime add table public.red_packets;
    exception when duplicate_object then null;
    end;
    begin
      alter publication supabase_realtime add table public.red_packet_claims;
    exception when duplicate_object then null;
    end;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Create + share a packet into a thread
-- ---------------------------------------------------------------------------
drop function if exists public.red_packet_create(uuid, numeric, integer, text, text, text);
create or replace function public.red_packet_create(
  p_thread_id uuid,
  p_total numeric,
  p_count integer default 1,
  p_wish text default null,
  p_packet_type text default 'random',
  p_message text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $function$
declare
  v_uid text := auth.uid()::text;
  v_wallet public.wallets%rowtype;
  v_new_balance numeric;
  v_packet_id uuid;
  v_cur text;
  v_type text := lower(coalesce(nullif(btrim(p_packet_type), ''), 'random'));
  v_body text;
begin
  if v_uid is null then raise exception 'authentication_required'; end if;
  if not private.is_thread_member(p_thread_id) then raise exception 'not_a_member'; end if;
  if p_total is null or p_total <= 0 then raise exception 'invalid_amount'; end if;
  if p_count is null or p_count < 1 or p_count > 100 then raise exception 'invalid_share_count'; end if;
  if v_type not in ('random','equal') then v_type := 'random'; end if;
  if round(p_total, 2) < round(p_count * 0.01, 2) then raise exception 'amount_too_small'; end if;

  select * into v_wallet from public.wallets where uid = v_uid for update;
  if v_wallet.uid is null then raise exception 'wallet_missing'; end if;
  if v_wallet.available_balance < p_total then raise exception 'insufficient_wallet_balance'; end if;

  v_cur := upper(v_wallet.currency);
  v_new_balance := v_wallet.available_balance - p_total;

  update public.wallets
     set available_balance = v_new_balance, version = version + 1, updated_at = now()
   where uid = v_uid;

  insert into public.red_packets(sender_uid, thread_id, total_amount, remaining_amount, share_count, currency, packet_type, wish, status, expires_at)
  values (v_uid, p_thread_id, p_total, p_total, p_count, v_cur, v_type, nullif(btrim(p_wish), ''), 'open', now() + interval '24 hours')
  returning id into v_packet_id;

  insert into public.wallet_ledger(wallet_uid, user_id, entry_type, amount, balance_after, reference_type, reference_id, idempotency_key, metadata)
  values (v_uid, v_uid, 'debit', p_total, v_new_balance, 'red_packet', v_packet_id::text,
          'rp-lock-' || v_packet_id::text,
          jsonb_build_object('packet_id', v_packet_id, 'count', p_count, 'packet_type', v_type));

  v_body := coalesce(nullif(btrim(p_message), ''), 'أرسل حزمة حمراء 🧧');
  insert into public.chat_messages(thread_id, sender_id, body, metadata)
  values (p_thread_id, v_uid, v_body,
          jsonb_build_object('kind', 'red_packet', 'packet_id', v_packet_id, 'amount', p_total, 'count', p_count, 'currency', v_cur));

  return v_packet_id;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Open a packet (one share per user, random or equal)
-- ---------------------------------------------------------------------------
drop function if exists public.red_packet_open(uuid);
create or replace function public.red_packet_open(p_packet_id uuid)
returns table(packet_id uuid, amount numeric, already_opened boolean, finished boolean, sender_uid text, remaining_amount numeric, opened_count integer, share_count integer, currency text, wish text)
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $function$
declare
  v_uid text := auth.uid()::text;
  v_packet public.red_packets%rowtype;
  v_existing numeric;
  v_share numeric;
  v_new_balance numeric;
  v_remaining integer;
  v_new_remaining numeric;
  v_final_status text;
  v_final_remaining numeric;
  v_final_opened integer;
begin
  if v_uid is null then raise exception 'authentication_required'; end if;

  select * into v_packet from public.red_packets where id = p_packet_id for update;
  if v_packet.id is null then raise exception 'packet_not_found'; end if;
  if not private.is_thread_member(v_packet.thread_id) then raise exception 'not_a_member'; end if;

  select c.amount into v_existing from public.red_packet_claims c
   where c.packet_id = p_packet_id and c.uid = v_uid;
  if v_existing is not null then
    return query select v_packet.id, v_existing, true,
      (v_packet.status in ('finished','expired','reclaimed')),
      v_packet.sender_uid, v_packet.remaining_amount, v_packet.opened_count, v_packet.share_count, v_packet.currency, v_packet.wish;
    return;
  end if;

  if v_packet.status <> 'open' or v_packet.expires_at <= now() or v_packet.remaining_amount <= 0 then
    return query select v_packet.id, 0::numeric, false, true,
      v_packet.sender_uid, v_packet.remaining_amount, v_packet.opened_count, v_packet.share_count, v_packet.currency, v_packet.wish;
    return;
  end if;

  v_remaining := v_packet.share_count - v_packet.opened_count;
  if v_remaining <= 1 then
    v_share := v_packet.remaining_amount;
  elsif v_packet.packet_type = 'equal' then
    v_share := round(v_packet.total_amount / v_packet.share_count, 2);
    if v_share > v_packet.remaining_amount then v_share := v_packet.remaining_amount; end if;
  else
    -- Random share in [0.01, 2*avg], capped so the remaining shares each keep >= 0.01.
    v_share := round((0.01 + random() * greatest(0.01, (2.0 * v_packet.remaining_amount / v_remaining) - 0.01))::numeric, 2);
    v_share := least(v_share, v_packet.remaining_amount - (v_remaining - 1) * 0.01);
    if v_share < 0.01 then v_share := 0.01; end if;
  end if;

  v_new_remaining := round(v_packet.remaining_amount - v_share, 2);
  update public.red_packets rp
     set remaining_amount = v_new_remaining,
         opened_count = rp.opened_count + 1,
         status = case when rp.opened_count + 1 >= rp.share_count or v_new_remaining <= 0 then 'finished' else 'open' end,
         finished_at = case when rp.opened_count + 1 >= rp.share_count or v_new_remaining <= 0 then now() else null end
   where rp.id = p_packet_id;

  insert into public.red_packet_claims(packet_id, uid, amount)
  values (p_packet_id, v_uid, v_share);

  select available_balance into v_new_balance from public.wallets where uid = v_uid for update;
  if v_new_balance is null then
    insert into public.wallets(uid, currency, status, available_balance, metadata, version, owner_uid, account_type)
    values (v_uid, v_packet.currency, 'active', 0, '{}'::jsonb, 0, v_uid, 'customer')
    returning available_balance into v_new_balance;
  end if;
  v_new_balance := v_new_balance + v_share;
  update public.wallets set available_balance = v_new_balance, version = version + 1, updated_at = now()
   where uid = v_uid;

  insert into public.wallet_ledger(wallet_uid, user_id, entry_type, amount, balance_after, reference_type, reference_id, idempotency_key, metadata)
  values (v_uid, v_uid, 'credit', v_share, v_new_balance, 'red_packet_claim', p_packet_id::text,
          'rp-claim-' || p_packet_id::text || '-' || v_uid,
          jsonb_build_object('packet_id', p_packet_id, 'sender', v_packet.sender_uid));

  perform private.notify_user(
    v_packet.sender_uid, 'red_packet', 'فُتحت حزمتك الحمراء 🧧',
    'حصل ' || coalesce((select nullif(btrim(u.name), '') from public.users u where u.uid = v_uid), 'أحد الأعضاء') || ' على ' || v_share || ' ' || v_packet.currency,
    jsonb_build_object('packet_id', p_packet_id, 'amount', v_share, 'currency', v_packet.currency)
  );

  select rp.status, rp.remaining_amount, rp.opened_count
    into v_final_status, v_final_remaining, v_final_opened
    from public.red_packets rp where rp.id = p_packet_id;

  return query select v_packet.id, v_share, false,
    (v_final_status in ('finished','expired','reclaimed')),
    v_packet.sender_uid, v_final_remaining, v_final_opened,
    v_packet.share_count, v_packet.currency, v_packet.wish;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Packet details for the detail screen (share list + sender/remaining)
-- ---------------------------------------------------------------------------
drop function if exists public.red_packet_details(uuid);
create or replace function public.red_packet_details(p_packet_id uuid)
returns table(packet_id uuid, sender_uid text, thread_id uuid, total_amount numeric, remaining_amount numeric, share_count integer, opened_count integer, currency text, packet_type text, wish text, status text, expires_at timestamptz, my_amount numeric)
language sql
stable
security definer
set search_path = pg_catalog, public, auth, private
as $function$
  select p.id, p.sender_uid, p.thread_id, p.total_amount, p.remaining_amount, p.share_count,
         p.opened_count, p.currency, p.packet_type, p.wish, p.status, p.expires_at,
         (select c.amount from public.red_packet_claims c where c.packet_id = p.id and c.uid = auth.uid()::text)
  from public.red_packets p
  where p.id = p_packet_id
    and (private.is_thread_member(p.thread_id) or private.is_platform_staff());
$function$;

drop function if exists public.red_packet_claims_list(uuid);
create or replace function public.red_packet_claims_list(p_packet_id uuid)
returns table(uid text, name text, amount numeric, created_at timestamptz)
language sql
stable
security definer
set search_path = pg_catalog, public, auth, private
as $function$
  select c.uid, coalesce(nullif(btrim(u.name), ''), 'مستخدم الفائق') as name, c.amount, c.created_at
  from public.red_packet_claims c
  left join public.users u on u.uid = c.uid
  where c.packet_id = p_packet_id
    and exists (select 1 from public.red_packets p where p.id = p_packet_id and private.is_thread_member(p.thread_id))
  order by c.created_at;
$function$;

-- ---------------------------------------------------------------------------
-- Sender reclaims the unopened balance of an expired/finished packet
-- ---------------------------------------------------------------------------
drop function if exists public.red_packet_reclaim(uuid);
create or replace function public.red_packet_reclaim(p_packet_id uuid)
returns numeric
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $function$
declare
  v_uid text := auth.uid()::text;
  v_packet public.red_packets%rowtype;
  v_new_balance numeric;
begin
  if v_uid is null then raise exception 'authentication_required'; end if;

  select * into v_packet from public.red_packets where id = p_packet_id for update;
  if v_packet.id is null then raise exception 'packet_not_found'; end if;
  if v_packet.sender_uid <> v_uid then raise exception 'not_sender'; end if;
  if v_packet.status = 'reclaimed' then
    select available_balance into v_new_balance from public.wallets where uid = v_uid;
    return coalesce(v_new_balance, 0);
  end if;
  if v_packet.remaining_amount <= 0 then
    update public.red_packets set status = 'finished' where id = p_packet_id;
    select available_balance into v_new_balance from public.wallets where uid = v_uid;
    return coalesce(v_new_balance, 0);
  end if;
  if v_packet.status = 'open' and v_packet.expires_at > now() then raise exception 'packet_not_expired'; end if;

  select available_balance into v_new_balance from public.wallets where uid = v_uid for update;
  v_new_balance := v_new_balance + v_packet.remaining_amount;
  update public.wallets set available_balance = v_new_balance, version = version + 1, updated_at = now()
   where uid = v_uid;

  insert into public.wallet_ledger(wallet_uid, user_id, entry_type, amount, balance_after, reference_type, reference_id, idempotency_key, metadata)
  values (v_uid, v_uid, 'credit', v_packet.remaining_amount, v_new_balance, 'red_packet_refund', p_packet_id::text,
          'rp-refund-' || p_packet_id::text,
          jsonb_build_object('packet_id', p_packet_id));

  update public.red_packets set status = 'reclaimed', remaining_amount = 0, finished_at = now()
   where id = p_packet_id;

  return v_new_balance;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Expiry sweep (best effort; no-op when pg_cron is unavailable)
-- ---------------------------------------------------------------------------
create or replace function private.red_packet_expire_sweep()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $function$
declare
  v_count integer := 0;
begin
  update public.red_packets
     set status = 'expired', finished_at = now()
   where status = 'open' and expires_at <= now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      perform cron.unschedule('alfaeq-red-packet-expire');
    exception when others then
      null;
    end;
    perform cron.schedule(
      'alfaeq-red-packet-expire',
      '*/15 * * * *',
      $cron$select private.red_packet_expire_sweep()$cron$
    );
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
revoke all on function public.red_packet_create(uuid, numeric, integer, text, text, text) from public, anon;
revoke all on function public.red_packet_open(uuid) from public, anon;
revoke all on function public.red_packet_details(uuid) from public, anon;
revoke all on function public.red_packet_claims_list(uuid) from public, anon;
revoke all on function public.red_packet_reclaim(uuid) from public, anon;
grant execute on function public.red_packet_create(uuid, numeric, integer, text, text, text) to authenticated;
grant execute on function public.red_packet_open(uuid) to authenticated;
grant execute on function public.red_packet_details(uuid) to authenticated;
grant execute on function public.red_packet_claims_list(uuid) to authenticated;
grant execute on function public.red_packet_reclaim(uuid) to authenticated;
