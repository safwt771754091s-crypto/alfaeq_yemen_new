-- WeChat Pay-style peer-to-peer transfer.
-- This is the ONLY client-initiated wallet mutation: it moves funds from the
-- caller to another user atomically (no minting). SECURITY DEFINER so it can
-- touch the counterparty's wallet and ledger, which RLS hides from clients.
--
-- Concurrency: rows are locked in ascending uid order to avoid deadlocks
-- between opposite transfers. Idempotency is enforced by the unique ledger key.

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
set search_path to ''
as $function$
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
    select * into v_sender from public.wallets where uid = v_uid and currency = v_cur for update;
    select * into v_recipient from public.wallets where uid = v_to and currency = v_cur for update;
  else
    select * into v_recipient from public.wallets where uid = v_to and currency = v_cur for update;
    select * into v_sender from public.wallets where uid = v_uid and currency = v_cur for update;
  end if;

  if v_sender.uid is null then raise exception 'sender_wallet_missing'; end if;

  -- Replay of a completed transfer: return the (already updated) balance.
  if exists (select 1 from public.wallet_ledger where idempotency_key = p_idempotency_key) then
    return v_sender.available_balance;
  end if;

  if v_sender.available_balance < p_amount then raise exception 'insufficient_wallet_balance'; end if;

  if v_recipient.uid is null then
    insert into public.wallets(uid, currency, status, available_balance, version, owner_uid, account_type)
    values (v_to, v_cur, 'active', 0, 0, v_to, 'customer')
    on conflict (uid) do nothing;
    select * into v_recipient from public.wallets where uid = v_to and currency = v_cur for update;
    if v_recipient.uid is null then raise exception 'recipient_currency_mismatch'; end if;
  end if;

  v_new_sender := v_sender.available_balance - p_amount;
  v_new_recipient := v_recipient.available_balance + p_amount;

  update public.wallets set available_balance = v_new_sender, version = version + 1, updated_at = now()
   where uid = v_uid and currency = v_cur;
  update public.wallets set available_balance = v_new_recipient, version = version + 1, updated_at = now()
   where uid = v_to and currency = v_cur;

  insert into public.wallet_ledger(wallet_uid, user_id, entry_type, amount, balance_after, reference_type, reference_id, idempotency_key, metadata)
  values
    (v_uid, v_uid, 'debit', p_amount, v_new_sender, 'transfer_out', v_to, p_idempotency_key,
     jsonb_build_object('note', p_note, 'counterparty', v_to)),
    (v_to, v_to, 'credit', p_amount, v_new_recipient, 'transfer_in', v_uid, p_idempotency_key || ':in',
     jsonb_build_object('note', p_note, 'counterparty', v_uid));

  return v_new_sender;
end;
$function$;

revoke all on function public.wallet_transfer(text, numeric, text, text, text) from public, anon;
grant execute on function public.wallet_transfer(text, numeric, text, text, text) to authenticated;

-- Resolve a payee's display name (users RLS hides other rows from clients).
create or replace function public.lookup_payee_name(p_uid text)
returns text
language sql
security definer
set search_path to ''
as $function$
  select coalesce(nullif(trim(u.name), ''), 'مستخدم الفائق')
  from public.users u
  where u.uid = nullif(trim(p_uid), '');
$function$;

revoke all on function public.lookup_payee_name(text) from public, anon;
grant execute on function public.lookup_payee_name(text) to authenticated;
