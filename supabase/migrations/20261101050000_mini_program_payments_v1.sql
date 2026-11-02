-- In-mini-program payments (الدفع داخل البرامج المصغّرة) — a WeChat-style
-- checkout that lets a user pay a mini program from their in-app wallet. The
-- money moves atomically: the buyer is debited and the program's owning
-- Official Account is credited, with a receipt row in program_orders.
--
-- Additive only: one new table, RLS, and one SECURITY DEFINER RPC. It reuses
-- private.wallet_debit_internal / private.fx_convert and the wallet_ledger, so
-- it inherits the platform's currency-integrity and idempotency guarantees.

create table if not exists public.program_orders (
  id uuid primary key default gen_random_uuid(),
  program_id text references public.mini_programs(id) on delete set null,
  program_name text not null default '',
  account_id uuid references public.official_accounts(id) on delete set null,
  buyer_id uuid not null references auth.users(id) on delete cascade,
  title text not null default '',
  amount numeric not null check (amount > 0),
  currency text not null default 'USD',
  status text not null default 'paid' check (status in ('paid', 'refunded')),
  idempotency_key text not null unique,
  metadata jsonb not null default '{}'::jsonb,
  paid_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists program_orders_buyer_idx on public.program_orders (buyer_id, created_at desc);
create index if not exists program_orders_account_idx on public.program_orders (account_id, created_at desc);
create index if not exists program_orders_program_idx on public.program_orders (program_id, created_at desc);

alter table public.program_orders enable row level security;

-- Receipts are private: the buyer, the receiving account owner, or staff.
drop policy if exists program_orders_read on public.program_orders;
create policy program_orders_read on public.program_orders for select to authenticated
  using (
    buyer_id = auth.uid()
    or exists (select 1 from public.official_accounts a where a.id = account_id and a.owner_id = auth.uid())
    or private.is_platform_staff()
  );

-- Writes happen only through the SECURITY DEFINER RPC below, never directly.
revoke all on public.program_orders from public, anon;
grant select on public.program_orders to authenticated;
grant all on public.program_orders to service_role;

-- Pays a mini program from the caller's wallet. The program's owning Official
-- Account is credited (converted into its wallet currency); platform-owned
-- programs simply keep the funds. Idempotent: replaying the same key returns
-- the original receipt without charging again.
create or replace function public.pay_mini_program(
  p_program_id text,
  p_title text,
  p_amount numeric,
  p_currency text default 'USD',
  p_idempotency_key text default null
)
returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, auth, private
as $$
declare
  v_uid text := auth.uid()::text;
  v_cur text := upper(coalesce(nullif(btrim(p_currency), ''), 'USD'));
  v_key text := btrim(coalesce(p_idempotency_key, ''));
  v_program record;
  v_owner uuid;
  v_account_id uuid;
  v_order_id uuid;
  v_existing public.program_orders%rowtype;
  v_wallet public.wallets%rowtype;
  v_merchant_wallet public.wallets%rowtype;
  v_credit numeric;
  v_merchant_credited boolean := false;
begin
  if v_uid is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if length(v_key) < 8 then
    raise exception 'invalid_idempotency_key';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_amount';
  end if;

  -- Idempotent retry: same key returns the original receipt, no double charge.
  select * into v_existing from public.program_orders where idempotency_key = v_key;
  if v_existing.id is not null then
    return jsonb_build_object(
      'ok', true, 'replayed', true, 'order_id', v_existing.id,
      'amount', v_existing.amount, 'currency', v_existing.currency
    );
  end if;

  select m.id, m.name, m.account_id into v_program
  from public.mini_programs m
  where m.id = p_program_id and m.status = 'active';
  if v_program.id is null then
    raise exception 'program_not_found';
  end if;
  v_account_id := v_program.account_id;
  if v_account_id is not null then
    select a.owner_id into v_owner from public.official_accounts a where a.id = v_account_id;
  end if;

  -- Align a brand-new / zero-balance buyer wallet to the payment currency so a
  -- first purchase in the catalog currency is not blocked by the YER default.
  select * into v_wallet from public.wallets where uid = v_uid for update;
  if v_wallet.uid is null then
    insert into public.wallets(uid, currency, status, available_balance, version, owner_uid, account_type)
    values (v_uid, v_cur, 'active', 0, 0, v_uid, 'customer')
    returning * into v_wallet;
  elsif v_wallet.available_balance = 0 and upper(v_wallet.currency) <> v_cur then
    update public.wallets set currency = v_cur, version = version + 1, updated_at = now()
    where uid = v_uid;
  end if;

  insert into public.program_orders(program_id, program_name, account_id, buyer_id, title, amount, currency, idempotency_key)
  values (v_program.id, v_program.name, v_account_id, auth.uid(), coalesce(nullif(btrim(p_title), ''), v_program.name), p_amount, v_cur, v_key)
  returning id into v_order_id;

  -- Buyer debit (raises 'insufficient wallet balance' if short; the whole
  -- transaction then rolls back leaving no order and no charge).
  perform private.wallet_debit_internal(p_amount, v_cur, 'mppay:' || v_key, 'program_order', v_order_id::text);

  -- Credit the owning account (unless the buyer owns it or it is platform-run).
  if v_owner is not null and v_owner::text <> v_uid then
    select * into v_merchant_wallet from public.wallets where uid = v_owner::text for update;
    if v_merchant_wallet.uid is null then
      insert into public.wallets(uid, currency, status, available_balance, version, owner_uid, account_type)
      values (v_owner::text, v_cur, 'active', 0, 0, v_owner::text, 'merchant')
      returning * into v_merchant_wallet;
    end if;
    if upper(v_merchant_wallet.currency) = v_cur then
      v_credit := p_amount;
    else
      v_credit := private.fx_convert(p_amount, v_cur, v_merchant_wallet.currency);
    end if;
    update public.wallets
       set available_balance = available_balance + v_credit, version = version + 1, updated_at = now()
     where uid = v_merchant_wallet.uid;
    insert into public.wallet_ledger(wallet_uid, user_id, entry_type, amount, balance_after, reference_type, reference_id, idempotency_key)
    values (v_merchant_wallet.uid, v_merchant_wallet.uid, 'credit', v_credit,
            v_merchant_wallet.available_balance + v_credit, 'program_order', v_order_id::text, 'mppay:' || v_key || ':merchant');
    v_merchant_credited := true;
  end if;

  return jsonb_build_object(
    'ok', true, 'replayed', false, 'order_id', v_order_id,
    'amount', p_amount, 'currency', v_cur,
    'program_id', v_program.id, 'account_id', v_account_id,
    'merchant_credited', v_merchant_credited
  );
end $$;

revoke all on function public.pay_mini_program(text, text, numeric, text, text) from public, anon;
grant execute on function public.pay_mini_program(text, text, numeric, text, text) to authenticated, service_role;
