-- Official Account sales dashboard (لوحة مبيعات الحساب الرسمي) — a WeChat
-- 商家后台-style view for account owners: revenue, order counts, per-program
-- breakdown and recent receipts, plus a seller-initiated refund.
--
-- Additive only. Reads are owner-scoped via a SECURITY DEFINER RPC (no broad
-- table grants); the refund reuses private.wallet_debit_internal to claw the
-- money back from the seller and credit the buyer, idempotently.

-- ---------------------------------------------------------------------------
-- Owner-only sales summary for one Official Account.
-- ---------------------------------------------------------------------------
create or replace function public.account_sales_summary(p_account_id uuid)
returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, auth, private
as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
  v_total numeric := 0;
  v_month numeric := 0;
  v_paid int := 0;
  v_refunded int := 0;
  v_by_program jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  select a.owner_id into v_owner from public.official_accounts a where a.id = p_account_id;
  if v_owner is null then
    raise exception 'account_not_found';
  end if;
  if v_owner <> v_uid and not private.is_platform_staff() then
    raise exception 'not_account_owner' using errcode = '42501';
  end if;

  select
    coalesce(sum(amount) filter (where status = 'paid'), 0),
    coalesce(sum(amount) filter (where status = 'paid' and created_at >= date_trunc('month', now())), 0),
    count(*) filter (where status = 'paid'),
    count(*) filter (where status = 'refunded')
  into v_total, v_month, v_paid, v_refunded
  from public.program_orders
  where account_id = p_account_id;

  select coalesce(jsonb_agg(x order by x.total desc), '[]'::jsonb) into v_by_program
  from (
    select
      o.program_id,
      coalesce(max(o.program_name), o.program_id) as program_name,
      sum(o.amount) as total,
      count(*) as orders
    from public.program_orders o
    where o.account_id = p_account_id and o.status = 'paid'
    group by o.program_id
  ) x;

  return jsonb_build_object(
    'account_id', p_account_id,
    'currency', 'USD',
    'total_revenue', v_total,
    'month_revenue', v_month,
    'paid_orders', v_paid,
    'refunded_orders', v_refunded,
    'by_program', v_by_program
  );
end $$;

-- ---------------------------------------------------------------------------
-- Owner-only recent receipts for one Official Account.
-- ---------------------------------------------------------------------------
create or replace function public.account_sales_orders(
  p_account_id uuid,
  p_limit int default 50
)
returns table (
  id uuid,
  program_id text,
  program_name text,
  title text,
  amount numeric,
  currency text,
  status text,
  buyer_id uuid,
  created_at timestamptz
)
language plpgsql security definer set search_path = pg_catalog, public, auth, private
as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
begin
  if v_uid is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  select a.owner_id into v_owner from public.official_accounts a where a.id = p_account_id;
  if v_owner is null then
    raise exception 'account_not_found';
  end if;
  if v_owner <> v_uid and not private.is_platform_staff() then
    raise exception 'not_account_owner' using errcode = '42501';
  end if;

  return query
  select o.id, o.program_id, o.program_name, o.title, o.amount, o.currency,
         o.status, o.buyer_id, o.created_at
  from public.program_orders o
  where o.account_id = p_account_id
  order by o.created_at desc
  limit greatest(1, least(coalesce(p_limit, 50), 200));
end $$;

-- ---------------------------------------------------------------------------
-- Seller-initiated refund: reverses a paid program order. Only the owning
-- account owner may refund; their wallet is debited (in the seller wallet's
-- currency, converted from the sale currency) and the buyer is credited. The
-- receipt is marked refunded. Idempotent per order.
-- ---------------------------------------------------------------------------
create or replace function public.refund_program_order(
  p_order_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, auth, private
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.program_orders%rowtype;
  v_owner uuid;
  v_seller_cur text;
  v_debit numeric;
  v_buyer_wallet public.wallets%rowtype;
  v_credit numeric;
begin
  if v_uid is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;

  select * into v_order from public.program_orders where id = p_order_id for update;
  if v_order.id is null then
    raise exception 'order_not_found';
  end if;

  if v_order.account_id is not null then
    select a.owner_id into v_owner from public.official_accounts a where a.id = v_order.account_id;
  end if;
  -- Only the seller can refund (private.wallet_debit_internal debits the
  -- caller's own wallet, so staff cannot reverse on a seller's behalf).
  if v_owner is null or v_owner <> v_uid then
    raise exception 'not_account_owner' using errcode = '42501';
  end if;

  if v_order.status = 'refunded' then
    return jsonb_build_object('ok', true, 'replayed', true, 'order_id', v_order.id, 'status', 'refunded');
  end if;
  if v_order.status <> 'paid' then
    raise exception 'order_not_refundable';
  end if;

  -- Claw the money back from the seller's wallet first, in the wallet's own
  -- currency. If the wallet is short this raises and the whole refund rolls
  -- back, so the buyer is never credited out of thin air.
  select upper(currency) into v_seller_cur from public.wallets where uid = v_uid::text;
  v_seller_cur := coalesce(v_seller_cur, upper(v_order.currency));
  v_debit := case when v_seller_cur = upper(v_order.currency)
                  then v_order.amount
                  else private.fx_convert(v_order.amount, v_order.currency, v_seller_cur) end;
  begin
    perform private.wallet_debit_internal(
      v_debit, v_seller_cur,
      'mprefund:' || v_order.id::text, 'program_order_refund', v_order.id::text
    );
  exception when others then
    raise exception 'insufficient_seller_balance';
  end;

  -- Credit the buyer in whatever currency their wallet already uses.
  select * into v_buyer_wallet from public.wallets where uid = v_order.buyer_id::text for update;
  if v_buyer_wallet.uid is null then
    insert into public.wallets(uid, currency, status, available_balance, version, owner_uid, account_type)
    values (v_order.buyer_id::text, v_order.currency, 'active', 0, 0, v_order.buyer_id::text, 'customer')
    returning * into v_buyer_wallet;
  end if;
  if upper(v_buyer_wallet.currency) = upper(v_order.currency) then
    v_credit := v_order.amount;
  else
    v_credit := private.fx_convert(v_order.amount, v_order.currency, v_buyer_wallet.currency);
  end if;
  update public.wallets
     set available_balance = available_balance + v_credit, version = version + 1, updated_at = now()
   where uid = v_buyer_wallet.uid;
  insert into public.wallet_ledger(wallet_uid, user_id, entry_type, amount, balance_after, reference_type, reference_id, idempotency_key)
  values (v_buyer_wallet.uid, v_buyer_wallet.uid, 'credit', v_credit,
          v_buyer_wallet.available_balance + v_credit, 'program_order_refund', v_order.id::text, 'mprefund:' || v_order.id::text || ':buyer');

  update public.program_orders
     set status = 'refunded',
         metadata = metadata || jsonb_build_object('refund_reason', coalesce(p_reason, ''), 'refunded_at', now())
   where id = v_order.id;

  perform private.notify_user(
    v_order.buyer_id::text, 'program_refund',
    'تم استرداد مبلغ طلبك',
    'أُعيد مبلغ ' || v_order.amount || ' ' || v_order.currency || ' إلى محفظتك.',
    jsonb_build_object('order_id', v_order.id, 'program_id', v_order.program_id)
  );

  return jsonb_build_object('ok', true, 'replayed', false, 'order_id', v_order.id, 'status', 'refunded');
end $$;

revoke all on function public.account_sales_summary(uuid) from public, anon;
revoke all on function public.account_sales_orders(uuid, int) from public, anon;
revoke all on function public.refund_program_order(uuid, text) from public, anon;
grant execute on function public.account_sales_summary(uuid) to authenticated, service_role;
grant execute on function public.account_sales_orders(uuid, int) to authenticated, service_role;
grant execute on function public.refund_program_order(uuid, text) to authenticated, service_role;
