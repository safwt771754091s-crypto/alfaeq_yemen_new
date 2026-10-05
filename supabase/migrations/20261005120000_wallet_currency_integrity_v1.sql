-- Wallet currency integrity.
--
-- The catalog is priced in a single currency (currently USD), but the wallet
-- model is one row per user: wallets.uid is the primary key. The previous
-- credit implementation assumed a (uid,currency) wallet and crashed with a
-- primary-key violation whenever the wallet's stored currency differed from the
-- requested one. It also never guarded against a currency change, so a caller
-- could relabel a funded YER wallet as USD and make its balance spendable 1:1.
--
-- This migration makes the single-wallet-per-user rule explicit:
--   * credit/debit operate on the user's existing wallet regardless of the
--     requested currency, and reject a currency that differs from a wallet that
--     holds a balance (no relabelling of funds);
--   * provisioning aligns a brand-new/zero-balance wallet to the requested
--     currency (so checkout in the catalog currency works);
--   * wallets are backfilled to the catalog currency when the catalog has a
--     single currency.

-- 1) Credit: never insert a duplicate wallet; enforce currency integrity.
create or replace function private.wallet_credit_internal(
  p_amount numeric,
  p_currency text default 'YER',
  p_idempotency_key text default null,
  p_reference_type text default null,
  p_reference_id text default null
)
returns numeric
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  w public.wallets%rowtype;
  b numeric;
  v_cur text := upper(coalesce(nullif(btrim(p_currency), ''), 'YER'));
begin
  if auth.uid() is null or p_amount <= 0 or p_idempotency_key is null then
    raise exception 'invalid wallet operation';
  end if;

  select * into w from public.wallets where uid = auth.uid()::text for update;

  if w.uid is null then
    insert into public.wallets(uid, currency, status, available_balance, metadata, version, owner_uid, account_type)
    values (auth.uid()::text, v_cur, 'active', 0, '{}'::jsonb, 0, auth.uid()::text, 'customer')
    returning * into w;
  end if;

  if exists(select 1 from public.wallet_ledger where idempotency_key = p_idempotency_key) then
    return w.available_balance;
  end if;

  if upper(w.currency) <> v_cur then
    if w.available_balance = 0 then
      update public.wallets set currency = v_cur, version = version + 1, updated_at = now()
       where uid = w.uid;
      w.currency := v_cur;
    else
      raise exception 'wallet_currency_mismatch';
    end if;
  end if;

  b := w.available_balance + p_amount;
  update public.wallets set available_balance = b, version = version + 1, updated_at = now()
   where uid = w.uid;
  insert into public.wallet_ledger(wallet_uid, user_id, entry_type, amount, balance_after, reference_type, reference_id, idempotency_key)
  values(w.uid, auth.uid()::text, 'credit', p_amount, b, p_reference_type, p_reference_id, p_idempotency_key);
  return b;
end;
$$;

-- 2) Debit: same single-wallet rule.
create or replace function private.wallet_debit_internal(
  p_amount numeric,
  p_currency text default 'YER',
  p_idempotency_key text default null,
  p_reference_type text default null,
  p_reference_id text default null
)
returns numeric
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  w public.wallets%rowtype;
  b numeric;
  v_cur text := upper(coalesce(nullif(btrim(p_currency), ''), 'YER'));
begin
  if auth.uid() is null or p_amount <= 0 or p_idempotency_key is null then
    raise exception 'invalid wallet operation';
  end if;

  select * into w from public.wallets where uid = auth.uid()::text for update;
  if w.uid is null or w.available_balance < p_amount then
    raise exception 'insufficient wallet balance';
  end if;
  if upper(w.currency) <> v_cur then
    raise exception 'wallet_currency_mismatch';
  end if;
  if exists(select 1 from public.wallet_ledger where idempotency_key = p_idempotency_key) then
    return w.available_balance;
  end if;

  b := w.available_balance - p_amount;
  update public.wallets set available_balance = b, version = version + 1, updated_at = now()
   where uid = w.uid;
  insert into public.wallet_ledger(wallet_uid, user_id, entry_type, amount, balance_after, reference_type, reference_id, idempotency_key)
  values(w.uid, auth.uid()::text, 'debit', p_amount, b, p_reference_type, p_reference_id, p_idempotency_key);
  return b;
end;
$$;

-- 3) Provisioning: align a zero-balance wallet to the requested currency.
create or replace function private.ensure_my_wallet_impl(
  p_currency text default 'YER',
  p_account_type text default 'customer'
)
returns public.wallets
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  v_uid text;
  v_wallet public.wallets;
  v_account_id text;
  v_cur text := upper(coalesce(nullif(btrim(p_currency), ''), 'YER'));
begin
  v_uid := auth.uid()::text;
  if v_uid is null then
    raise exception 'authentication required';
  end if;
  if coalesce(p_account_type, '') not in ('customer','merchant','driver','platform') then
    raise exception 'invalid account type';
  end if;

  select id into v_account_id from public.platform_accounts
    where owner_uid = v_uid and account_type = p_account_type and status = 'active'
    order by created_at limit 1;
  if v_account_id is null then
    v_account_id := 'acct-' || v_uid || '-' || lower(p_account_type);
    insert into public.platform_accounts(id,account_type,owner_uid,display_name,status,default_currency,metadata)
    values(v_account_id,p_account_type,v_uid,coalesce(p_account_type,'customer'),'active',v_cur,'{}'::jsonb)
    on conflict (id) do nothing;
  end if;

  select * into v_wallet from public.wallets where uid = v_uid for update;
  if v_wallet.uid is null then
    insert into public.wallets(uid,currency,status,available_balance,metadata,version,account_id,account_type,owner_uid)
    values(v_uid,v_cur,'active',0,'{}'::jsonb,0,v_account_id,p_account_type,v_uid)
    returning * into v_wallet;
  else
    update public.wallets
       set account_id = coalesce(account_id, v_account_id),
           account_type = coalesce(account_type, p_account_type),
           owner_uid = coalesce(owner_uid, v_uid),
           currency = case when available_balance = 0 then v_cur else currency end,
           updated_at = now()
     where uid = v_uid
    returning * into v_wallet;
  end if;

  return v_wallet;
end;
$$;

-- 4) Transfer: create the recipient wallet without risking a duplicate-key
--    crash, and return a clear error when the recipient wallet's currency
--    differs from the transfer currency.
create or replace function public.wallet_transfer(
  p_to_uid text,
  p_amount numeric,
  p_currency text default 'YER',
  p_idempotency_key text default null,
  p_note text default null
)
returns numeric
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  v_uid text := auth.uid()::text;
  v_cur text := upper(coalesce(nullif(trim(p_currency), ''), 'YER'));
  v_sender public.wallets%rowtype;
  v_recipient public.wallets%rowtype;
  v_new_sender numeric;
  v_new_recipient numeric;
  v_to text := nullif(trim(p_to_uid), '');
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'invalid_amount'; end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then raise exception 'idempotency_required'; end if;
  if v_to is null then raise exception 'recipient_required'; end if;
  if v_to = v_uid then raise exception 'cannot_pay_self'; end if;
  if not exists (select 1 from public.users u where u.uid = v_to) then raise exception 'recipient_not_found'; end if;

  -- Lock both wallets in a deterministic order to avoid deadlocks.
  if v_uid < v_to then
    select * into v_sender from public.wallets where uid = v_uid for update;
    select * into v_recipient from public.wallets where uid = v_to for update;
  else
    select * into v_recipient from public.wallets where uid = v_to for update;
    select * into v_sender from public.wallets where uid = v_uid for update;
  end if;

  if v_sender.uid is null then raise exception 'sender_wallet_missing'; end if;
  if upper(v_sender.currency) <> v_cur then raise exception 'sender_currency_mismatch'; end if;

  -- Replay of a completed transfer: return the (already updated) balance.
  if exists (select 1 from public.wallet_ledger where idempotency_key = p_idempotency_key) then
    return v_sender.available_balance;
  end if;

  if v_sender.available_balance < p_amount then raise exception 'insufficient_wallet_balance'; end if;

  if v_recipient.uid is null then
    insert into public.wallets(uid, currency, status, available_balance, version, owner_uid, account_type)
    values (v_to, v_cur, 'active', 0, 0, v_to, 'customer')
    on conflict (uid) do nothing;
    select * into v_recipient from public.wallets where uid = v_to for update;
  end if;
  if upper(v_recipient.currency) <> v_cur then raise exception 'recipient_currency_mismatch'; end if;

  v_new_sender := v_sender.available_balance - p_amount;
  v_new_recipient := v_recipient.available_balance + p_amount;

  update public.wallets set available_balance = v_new_sender, version = version + 1, updated_at = now()
   where uid = v_uid;
  update public.wallets set available_balance = v_new_recipient, version = version + 1, updated_at = now()
   where uid = v_to;

  insert into public.wallet_ledger(wallet_uid, user_id, entry_type, amount, balance_after, reference_type, reference_id, idempotency_key, metadata)
  values
    (v_uid, v_uid, 'debit', p_amount, v_new_sender, 'transfer_out', v_to, p_idempotency_key,
     jsonb_build_object('note', p_note, 'counterparty', v_to)),
    (v_to, v_to, 'credit', p_amount, v_new_recipient, 'transfer_in', v_uid, p_idempotency_key || ':in',
     jsonb_build_object('note', p_note, 'counterparty', v_uid));

  return v_new_sender;
end;
$$;

-- 5) Backfill: when the catalog is priced in a single currency, any wallet that
--    holds no funds is aligned to it so checkout works out of the box.
do $$
declare
  v_cur text;
begin
  select min(currency) into v_cur
  from public.products
  where status in ('active','published') and currency is not null;
  if v_cur is not null
     and not exists (
       select 1 from public.products
       where status in ('active','published') and currency is not null and currency <> v_cur
     ) then
    update public.wallets set currency = v_cur, updated_at = now()
     where available_balance = 0 and currency <> v_cur;
  end if;
end $$;
