-- Wallet recharge vouchers (Alfaeq Yemen).
--
-- The wallet already supports transfers and idempotent credits, but there was
-- no way for a customer to fund it. Card gateways are scarce in the local
-- market, so the platform issues prepaid recharge codes that staff print or
-- sell, and the customer redeems inside the app. Additive only.

create table if not exists public.wallet_topup_vouchers (
  code text primary key,
  amount numeric not null check (amount > 0),
  currency text not null default 'USD',
  status text not null default 'active' check (status in ('active','redeemed','void')),
  redeemed_by text,
  redeemed_at timestamptz,
  created_by text,
  batch_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists wallet_topup_vouchers_status_idx on public.wallet_topup_vouchers(status);
create index if not exists wallet_topup_vouchers_batch_idx on public.wallet_topup_vouchers(batch_id);

alter table public.wallet_topup_vouchers enable row level security;

-- Only platform staff can read the voucher book directly; customers redeem
-- through the RPC below, so they never see unused codes.
drop policy if exists wallet_topup_vouchers_staff_read on public.wallet_topup_vouchers;
create policy wallet_topup_vouchers_staff_read on public.wallet_topup_vouchers
  for select to authenticated
  using (private.is_platform_staff());

-- ---------------------------------------------------------------------------
-- Issue a batch of vouchers (staff only). Returns the generated codes once;
-- they are not retrievable in plaintext afterwards for non-staff.
-- ---------------------------------------------------------------------------
create or replace function public.issue_wallet_vouchers(
  p_count integer,
  p_amount numeric,
  p_currency text default 'USD'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_uid text := auth.uid()::text;
  v_cur text := upper(coalesce(nullif(btrim(p_currency), ''), 'USD'));
  v_batch text := 'batch-' || replace(gen_random_uuid()::text, '-', '');
  v_codes text[] := '{}';
  v_code text;
  i integer;
begin
  if not private.is_platform_staff() then
    raise exception 'not_authorized';
  end if;
  if p_count is null or p_count < 1 or p_count > 500 then
    raise exception 'invalid_count';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_amount';
  end if;

  for i in 1..p_count loop
    loop
      v_code := 'ALF-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))
                        || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
      begin
        insert into public.wallet_topup_vouchers(code, amount, currency, created_by, batch_id)
        values (v_code, p_amount, v_cur, v_uid, v_batch);
        exit;
      exception when unique_violation then
        -- Extremely unlikely; regenerate and retry.
      end;
    end loop;
    v_codes := array_append(v_codes, v_code);
  end loop;

  return jsonb_build_object(
    'ok', true, 'batch_id', v_batch, 'amount', p_amount,
    'currency', v_cur, 'count', p_count, 'codes', to_jsonb(v_codes)
  );
end;
$$;

revoke all on function public.issue_wallet_vouchers(integer, numeric, text) from public, anon;
grant execute on function public.issue_wallet_vouchers(integer, numeric, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Redeem a voucher and credit the caller's wallet. The voucher row is locked
-- and marked redeemed in the same transaction, and the ledger credit uses the
-- voucher code as an idempotency key, so a retry can never double-credit.
-- ---------------------------------------------------------------------------
create or replace function public.redeem_wallet_voucher(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_uid text := auth.uid()::text;
  v_code text := upper(btrim(coalesce(p_code, '')));
  v_v public.wallet_topup_vouchers%rowtype;
  v_balance numeric;
begin
  if v_uid is null then raise exception 'authentication_required'; end if;
  if v_code = '' then raise exception 'code_required'; end if;

  select * into v_v from public.wallet_topup_vouchers where code = v_code for update;
  if not found then raise exception 'voucher_not_found'; end if;
  if v_v.status <> 'active' then raise exception 'voucher_already_used'; end if;

  v_balance := private.wallet_credit_internal(
    v_v.amount, v_v.currency, 'voucher:' || v_code, 'topup', v_code
  );

  update public.wallet_topup_vouchers
     set status = 'redeemed', redeemed_by = v_uid, redeemed_at = now(), updated_at = now()
   where code = v_code;

  return jsonb_build_object(
    'ok', true, 'code', v_code, 'amount', v_v.amount,
    'currency', v_v.currency, 'balance', v_balance
  );
end;
$$;

revoke all on function public.redeem_wallet_voucher(text) from public, anon;
grant execute on function public.redeem_wallet_voucher(text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Staff view of recent voucher batches.
-- ---------------------------------------------------------------------------
create or replace function public.list_wallet_vouchers(p_limit integer default 100)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_rows jsonb;
begin
  if not private.is_platform_staff() then
    raise exception 'not_authorized';
  end if;
  select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) into v_rows
    from (
      select code, amount, currency, status, batch_id, redeemed_by, redeemed_at, created_at
        from public.wallet_topup_vouchers
       order by created_at desc
       limit least(greatest(coalesce(p_limit, 100), 1), 500)
    ) t;
  return jsonb_build_object('ok', true, 'vouchers', v_rows);
end;
$$;

revoke all on function public.list_wallet_vouchers(integer) from public, anon;
grant execute on function public.list_wallet_vouchers(integer) to authenticated, service_role;
