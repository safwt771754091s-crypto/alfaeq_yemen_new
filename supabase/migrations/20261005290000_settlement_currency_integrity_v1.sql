-- Merchant settlement currency integrity.
--
-- Bug: `settle_order_to_merchant` credited each store owner the raw
-- order-currency amount directly into their wallet, with no conversion. A
-- wallet denominated in YER (the norm for Yemeni merchants) received USD
-- numbers as if they were YER, under-crediting the merchant ~1500x, and the
-- `wallet_currency` recorded in the ledger was misleading.
--
-- Fix: add a general currency converter and convert every settlement amount
-- from the order currency into the wallet's own currency before crediting.

-- General USD-based converter (rates are "units per 1 USD").
create or replace function private.fx_convert(p_amount numeric, p_from text, p_to text)
returns numeric
language plpgsql
security definer
stable
set search_path = pg_catalog, public, private
as $$
declare
  v_rates jsonb;
  v_from numeric;
  v_to numeric;
begin
  v_rates := public.get_fx_rates() -> 'rates';
  v_from := (v_rates ->> upper(coalesce(nullif(btrim(p_from), ''), 'USD')))::numeric;
  v_to := (v_rates ->> upper(coalesce(nullif(btrim(p_to), ''), 'USD')))::numeric;
  if v_from is null or v_from <= 0 or v_to is null or v_to <= 0 then
    raise exception 'unsupported_currency';
  end if;
  return round(coalesce(p_amount, 0) * v_to / v_from, 2);
end;
$$;

revoke all on function private.fx_convert(numeric, text, text) from public, anon;
grant execute on function private.fx_convert(numeric, text, text) to authenticated, service_role;

create or replace function private.settle_order_to_merchant(p_order_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.orders%rowtype;
  v_uid text := auth.uid()::text;
  v_entry record;
  v_wallet public.wallets%rowtype;
  v_new_balance numeric;
  v_key text;
  v_total numeric := 0;
  v_wallet_amount numeric;
  v_order_currency text;
  v_entries jsonb := '[]'::jsonb;
  v_authorized boolean := false;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.id is null then raise exception 'order_not_found'; end if;

  if v_uid is not null then
    select exists(
      select 1 from public.stores s
      where s.owner_id = v_uid and s.id = any(v_order.merchant_ids)
    ) into v_authorized;
    v_authorized := v_authorized
      or v_uid = v_order.customer_id
      or v_uid = v_order.driver_id
      or exists(
        select 1 from public.users u
        where u.uid = v_uid and (coalesce(u.admin,false) or coalesce(u.owner,false) or coalesce(u.developer,false))
      );
    if not v_authorized then raise exception 'not authorized'; end if;
  end if;

  if v_order.status <> 'delivered' then raise exception 'order_not_delivered'; end if;

  if coalesce((v_order.metadata -> 'settlement' ->> 'settled')::boolean, false) then
    return jsonb_build_object('ok', true, 'already_settled', true, 'settlement', v_order.metadata -> 'settlement');
  end if;

  v_order_currency := upper(coalesce(nullif(btrim(v_order.currency), ''), 'USD'));

  for v_entry in
    select oi.store_id,
           s.owner_id,
           sum(coalesce(oi.unit_price, 0) * oi.quantity) as amount
    from public.order_items oi
    left join public.stores s on s.id = oi.store_id
    where oi.order_id = p_order_id and oi.store_id is not null
    group by oi.store_id, s.owner_id
  loop
    -- Nothing to move for platform-owned stores or a self-purchase.
    if v_entry.owner_id is null or v_entry.owner_id = v_order.customer_id or coalesce(v_entry.amount, 0) <= 0 then
      continue;
    end if;

    v_key := 'settle:' || p_order_id || ':' || v_entry.owner_id;
    if exists(select 1 from public.wallet_ledger where idempotency_key = v_key) then
      v_total := v_total + v_entry.amount;
      v_entries := v_entries || jsonb_build_object('store_id', v_entry.store_id, 'owner_uid', v_entry.owner_id, 'amount', v_entry.amount);
      continue;
    end if;

    select * into v_wallet from public.wallets where uid = v_entry.owner_id for update;
    if v_wallet.uid is null then
      insert into public.wallets(uid, currency, status, available_balance, version, owner_uid, account_type)
      values (v_entry.owner_id, v_order_currency, 'active', 0, 0, v_entry.owner_id, 'merchant')
      returning * into v_wallet;
    end if;

    -- The wallet's own currency is authoritative: convert before crediting.
    if upper(v_wallet.currency) = v_order_currency then
      v_wallet_amount := v_entry.amount;
    else
      v_wallet_amount := private.fx_convert(v_entry.amount, v_order_currency, v_wallet.currency);
    end if;

    v_new_balance := v_wallet.available_balance + v_wallet_amount;
    update public.wallets
    set available_balance = v_new_balance, version = version + 1, updated_at = now()
    where uid = v_wallet.uid;

    insert into public.wallet_ledger(
      wallet_uid, user_id, entry_type, amount, balance_after,
      reference_type, reference_id, idempotency_key, metadata
    ) values (
      v_wallet.uid, v_entry.owner_id, 'credit', v_wallet_amount, v_new_balance,
      'order_settlement', p_order_id, v_key,
      jsonb_build_object(
        'store_id', v_entry.store_id,
        'order_currency', v_order_currency,
        'order_amount', v_entry.amount,
        'wallet_currency', v_wallet.currency,
        'wallet_amount', v_wallet_amount
      )
    );

    v_total := v_total + v_wallet_amount;
    v_entries := v_entries || jsonb_build_object(
      'store_id', v_entry.store_id, 'owner_uid', v_entry.owner_id,
      'amount', v_wallet_amount, 'currency', v_wallet.currency,
      'order_amount', v_entry.amount, 'order_currency', v_order_currency
    );
  end loop;

  update public.orders
  set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'settlement', jsonb_build_object(
          'settled', true,
          'settled_at', now(),
          'total_credited', v_total,
          'entries', v_entries
        )
      )
  where id = p_order_id;

  return jsonb_build_object('ok', true, 'settled', true, 'total_credited', v_total, 'entries', v_entries);
end
$function$;
