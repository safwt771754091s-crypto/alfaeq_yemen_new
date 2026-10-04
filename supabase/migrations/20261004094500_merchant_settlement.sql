-- Merchant settlement: credit each store owner when an order is delivered.
-- Additive: one private engine + one public wrapper + one auto-settle trigger.
--
-- Wallet tables/ACLs are locked down (private.wallet_credit_internal is not
-- grantable to clients), so settlement runs entirely server-side. Crediting is
-- idempotent per (order, store owner) via a deterministic ledger key, and the
-- order records its settlement block so re-runs are cheap no-ops.

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
      insert into public.wallets(uid, currency, status, available_balance, version)
      values (v_entry.owner_id, upper(coalesce(v_order.currency, 'YER')), 'active', 0, 0)
      returning * into v_wallet;
    end if;

    v_new_balance := v_wallet.available_balance + v_entry.amount;
    update public.wallets
    set available_balance = v_new_balance, version = version + 1, updated_at = now()
    where uid = v_wallet.uid;

    insert into public.wallet_ledger(
      wallet_uid, user_id, entry_type, amount, balance_after,
      reference_type, reference_id, idempotency_key, metadata
    ) values (
      v_wallet.uid, v_entry.owner_id, 'credit', v_entry.amount, v_new_balance,
      'order_settlement', p_order_id, v_key,
      jsonb_build_object(
        'store_id', v_entry.store_id,
        'order_currency', v_order.currency,
        'wallet_currency', v_wallet.currency
      )
    );

    v_total := v_total + v_entry.amount;
    v_entries := v_entries || jsonb_build_object('store_id', v_entry.store_id, 'owner_uid', v_entry.owner_id, 'amount', v_entry.amount);
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

create or replace function public.settle_order(p_order_id text)
returns jsonb
language sql
set search_path = ''
as $function$ select private.settle_order_to_merchant(p_order_id) $function$;

revoke all on function public.settle_order(text) from public, anon;
grant execute on function public.settle_order(text) to authenticated;

-- Auto-settle when an order reaches 'delivered'. A failure here must never
-- block the delivery transition, so it is swallowed; staff can retry with
-- public.settle_order.
create or replace function private.trg_order_settle_on_delivery()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.status = 'delivered' and coalesce(old.status, '') <> 'delivered' then
    begin
      perform private.settle_order_to_merchant(new.id);
    exception when others then
      null;
    end;
  end if;
  return new;
end
$function$;

drop trigger if exists order_settle_on_delivery on public.orders;
create trigger order_settle_on_delivery
  after update on public.orders
  for each row execute function private.trg_order_settle_on_delivery();
