-- Master bank deposits + absolute owner (Super Admin) controls.
--
-- 1) master_bank_accounts — the official Al-Kuraimi (بنك الكريمي) accounts the
--    app shows on the deposit screen (YER / SAR / USD).
-- 2) wallet_deposits — user deposit requests with a receipt reference and an
--    optional receipt image; reviewed (approve/reject) by the master owner.
-- 3) master_permissions — granular permission matrix for the master owner.
--
-- Additive only. Existing wallet/ledger objects are not altered.

-- ---------------------------------------------------------------------------
-- Master owner helper: DB-backed staff check (JWT claims may be absent).
-- ---------------------------------------------------------------------------
create or replace function private.is_master_owner()
returns boolean
language sql stable security definer
set search_path = pg_catalog, public, auth, private
as $$
  select exists (
    select 1 from public.users u
    where u.uid = auth.uid()::text
      and (coalesce(u.owner, false) or coalesce(u.admin, false)
           or u.role in ('owner', 'admin'))
  );
$$;
revoke all on function private.is_master_owner() from public, anon;
grant execute on function private.is_master_owner() to authenticated, service_role;

-- Recognise DB-backed staff in the platform-wide staff check as well, so the
-- owner reaches admin-only tables even when the JWT carries no app_role claim.
create or replace function private.is_platform_staff()
returns boolean
language sql stable security definer
set search_path = pg_catalog, public, auth, private
as $$
  select
    coalesce(auth.jwt()->>'app_role','') in ('admin','owner','developer')
    or coalesce((auth.jwt()->>'admin')::boolean,false)
    or coalesce((auth.jwt()->>'owner')::boolean,false)
    or coalesce((auth.jwt()->>'developer')::boolean,false)
    or coalesce(auth.jwt()->'app_metadata'->>'app_role','') in ('admin','owner','developer')
    or coalesce((auth.jwt()->'app_metadata'->>'admin')::boolean,false)
    or coalesce((auth.jwt()->'app_metadata'->>'owner')::boolean,false)
    or coalesce((auth.jwt()->'app_metadata'->>'developer')::boolean,false)
    or exists (
      select 1 from public.users u
      where u.uid = auth.uid()::text
        and (coalesce(u.owner,false) or coalesce(u.admin,false)
             or coalesce(u.developer,false)
             or u.role in ('owner','admin','developer'))
    );
$$;
revoke all on function private.is_platform_staff() from public, anon;
grant execute on function private.is_platform_staff() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 1) master_bank_accounts
-- ---------------------------------------------------------------------------
create table if not exists public.master_bank_accounts (
  id uuid primary key default gen_random_uuid(),
  currency text not null unique check (currency in ('YER','SAR','USD')),
  bank_name text not null default 'بنك الكريمي',
  account_name text not null default 'الفائق يمن',
  account_number text not null,
  iban text,
  branch text,
  instructions text,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.master_bank_accounts enable row level security;

-- Any signed-in user may read the active accounts (needed on the deposit screen).
drop policy if exists master_bank_accounts_read on public.master_bank_accounts;
create policy master_bank_accounts_read on public.master_bank_accounts
  for select to authenticated using (true);

-- Only the master owner manages them.
drop policy if exists master_bank_accounts_write on public.master_bank_accounts;
create policy master_bank_accounts_write on public.master_bank_accounts
  for all to authenticated
  using (private.is_master_owner())
  with check (private.is_master_owner());

grant select on public.master_bank_accounts to authenticated;
grant insert, update, delete on public.master_bank_accounts to authenticated;

-- Seed the three official accounts (idempotent).
insert into public.master_bank_accounts
  (currency, bank_name, account_name, account_number, instructions, sort_order)
values
  ('YER', 'بنك الكريمي', 'الفائق يمن', '3009540813', 'حوّل المبلغ بالريال اليمني إلى هذا الحساب ثم أدخل رقم الإيصال.', 1),
  ('SAR', 'بنك الكريمي', 'الفائق يمن', '3065094443', 'حوّل المبلغ بالريال السعودي إلى هذا الحساب ثم أدخل رقم الإيصال.', 2),
  ('USD', 'بنك الكريمي', 'الفائق يمن', '3065190868', 'حوّل المبلغ بالدولار الأمريكي إلى هذا الحساب ثم أدخل رقم الإيصال.', 3)
on conflict (currency) do update
  set bank_name = excluded.bank_name,
      account_number = excluded.account_number,
      instructions = excluded.instructions,
      sort_order = excluded.sort_order,
      updated_at = now();

-- ---------------------------------------------------------------------------
-- 2) wallet_deposits
-- ---------------------------------------------------------------------------
create table if not exists public.wallet_deposits (
  id uuid primary key default gen_random_uuid(),
  uid text not null,
  currency text not null check (currency in ('YER','SAR','USD')),
  amount numeric not null check (amount > 0),
  bank_account_id uuid references public.master_bank_accounts(id) on delete set null,
  receipt_ref text not null,
  receipt_url text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  credited boolean not null default false,
  balance_after numeric,
  reviewed_by text,
  reviewed_at timestamptz,
  review_note text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists wallet_deposits_uid_idx on public.wallet_deposits (uid, created_at desc);
create index if not exists wallet_deposits_status_idx on public.wallet_deposits (status, created_at desc);
create unique index if not exists wallet_deposits_receipt_ref_idx
  on public.wallet_deposits (currency, receipt_ref) where status <> 'rejected';

alter table public.wallet_deposits enable row level security;

-- A user reads their own deposits; the master owner reads every deposit.
drop policy if exists wallet_deposits_select on public.wallet_deposits;
create policy wallet_deposits_select on public.wallet_deposits
  for select to authenticated
  using (uid = auth.uid()::text or private.is_master_owner());

-- A user may create a pending deposit for themselves only.
drop policy if exists wallet_deposits_insert on public.wallet_deposits;
create policy wallet_deposits_insert on public.wallet_deposits
  for insert to authenticated
  with check (uid = auth.uid()::text and status = 'pending' and credited = false);

-- Only the master owner reviews (updates) deposits.
drop policy if exists wallet_deposits_update on public.wallet_deposits;
create policy wallet_deposits_update on public.wallet_deposits
  for update to authenticated
  using (private.is_master_owner())
  with check (private.is_master_owner());

grant select, insert on public.wallet_deposits to authenticated;
grant update on public.wallet_deposits to authenticated;

-- Realtime so the owner's review queue refreshes instantly.
do $$ begin
  alter publication supabase_realtime add table public.wallet_deposits;
exception when duplicate_object then null; when undefined_object then null; end $$;

-- ---------------------------------------------------------------------------
-- 3) master_permissions
-- ---------------------------------------------------------------------------
create table if not exists public.master_permissions (
  id uuid primary key default gen_random_uuid(),
  uid text not null,
  permission text not null,
  granted boolean not null default true,
  granted_by text,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (uid, permission)
);
create index if not exists master_permissions_uid_idx on public.master_permissions (uid);

alter table public.master_permissions enable row level security;

-- Only the master owner sees or edits the permission matrix.
drop policy if exists master_permissions_read on public.master_permissions;
create policy master_permissions_read on public.master_permissions
  for select to authenticated using (private.is_master_owner());

drop policy if exists master_permissions_write on public.master_permissions;
create policy master_permissions_write on public.master_permissions
  for all to authenticated
  using (private.is_master_owner())
  with check (private.is_master_owner());

grant select, insert, update, delete on public.master_permissions to authenticated;

-- Seed the full permission set for every existing owner account.
insert into public.master_permissions (uid, permission, granted, note)
select u.uid, p.permission, true, 'منح تلقائي لحساب المالك'
from public.users u
cross join (values
  ('wallet.deposits.review'),
  ('wallet.deposits.reject'),
  ('wallet.withdraw.review'),
  ('wallet.adjust'),
  ('admin.dashboard'),
  ('admin.users.manage'),
  ('admin.merchants.approve'),
  ('admin.payouts.review'),
  ('platform.settings'),
  ('platform.bank_accounts.manage')
) as p(permission)
where coalesce(u.owner,false) or coalesce(u.admin,false) or u.role in ('owner','admin')
on conflict (uid, permission) do nothing;

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

-- Create a pending deposit request for the caller.
create or replace function public.wallet_deposit_create(
  p_currency text,
  p_amount numeric,
  p_receipt_ref text,
  p_receipt_url text default null,
  p_bank_account_id uuid default null
)
returns public.wallet_deposits
language plpgsql security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  d public.wallet_deposits%rowtype;
  v_uid text := auth.uid()::text;
  v_cur text := upper(btrim(coalesce(p_currency, '')));
  v_ref text := btrim(coalesce(p_receipt_ref, ''));
begin
  if v_uid is null then raise exception 'authentication_required'; end if;
  if v_cur not in ('YER','SAR','USD') then raise exception 'invalid_currency'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'invalid_amount'; end if;
  if v_ref = '' then raise exception 'receipt_required'; end if;

  insert into public.wallet_deposits (uid, currency, amount, bank_account_id, receipt_ref, receipt_url, status)
  values (v_uid, v_cur, p_amount, p_bank_account_id, v_ref,
          nullif(btrim(coalesce(p_receipt_url, '')), ''), 'pending')
  returning * into d;

  return d;
end $$;

-- List deposits: the caller's own, or everything for the master owner.
create or replace function public.wallet_deposits_list(
  p_status text default null,
  p_limit integer default 100
)
returns setof public.wallet_deposits
language sql stable security definer
set search_path = pg_catalog, public, auth, private
as $$
  select d.*
  from public.wallet_deposits d
  where (private.is_master_owner() or d.uid = auth.uid()::text)
    and (p_status is null or d.status = p_status)
  order by d.created_at desc
  limit greatest(1, least(coalesce(p_limit, 100), 500));
$$;

-- Credit a specific user's wallet for a reviewed deposit (idempotent).
create or replace function private.deposit_credit(
  p_uid text,
  p_amount numeric,
  p_currency text,
  p_deposit_id uuid
)
returns numeric
language plpgsql security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  w public.wallets%rowtype;
  b numeric;
  v_key text := 'deposit:' || p_deposit_id::text;
  v_cur text := upper(btrim(coalesce(p_currency, 'YER')));
begin
  if exists (select 1 from public.wallet_ledger where idempotency_key = v_key) then
    select available_balance into b from public.wallets where uid = p_uid;
    return coalesce(b, 0);
  end if;

  select * into w from public.wallets where uid = p_uid for update;
  if w.uid is null then
    insert into public.wallets (uid, currency, status, available_balance, metadata, version, owner_uid, account_type)
    values (p_uid, v_cur, 'active', 0, '{}'::jsonb, 0, p_uid, 'customer')
    returning * into w;
  end if;

  if upper(w.currency) <> v_cur then
    if w.available_balance = 0 then
      update public.wallets set currency = v_cur, version = version + 1, updated_at = now() where uid = p_uid;
      w.currency := v_cur;
    else
      raise exception 'wallet_currency_mismatch: wallet=% deposit=%', w.currency, v_cur;
    end if;
  end if;

  b := w.available_balance + p_amount;
  update public.wallets set available_balance = b, version = version + 1, updated_at = now() where uid = p_uid;
  insert into public.wallet_ledger
    (wallet_uid, user_id, entry_type, amount, balance_after, reference_type, reference_id, idempotency_key, metadata)
  values
    (p_uid, p_uid, 'credit', p_amount, b, 'deposit', p_deposit_id::text, v_key,
     jsonb_build_object('currency', v_cur, 'source', 'bank_deposit'));
  return b;
end $$;
revoke all on function private.deposit_credit(text, numeric, text, uuid) from public, anon, authenticated;
grant execute on function private.deposit_credit(text, numeric, text, uuid) to service_role;

-- Approve or reject a deposit. Master owner only. Approval credits the wallet.
create or replace function public.wallet_deposit_decide(
  p_deposit_id uuid,
  p_approve boolean,
  p_note text default null
)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  d public.wallet_deposits%rowtype;
  b numeric;
begin
  if not private.is_master_owner() then raise exception 'not_authorized'; end if;

  select * into d from public.wallet_deposits where id = p_deposit_id for update;
  if not found then raise exception 'deposit_not_found'; end if;
  if d.status <> 'pending' then raise exception 'deposit_already_reviewed'; end if;

  if p_approve then
    b := private.deposit_credit(d.uid, d.amount, d.currency, d.id);
    update public.wallet_deposits
       set status = 'approved', credited = true, balance_after = b,
           reviewed_by = auth.uid()::text, reviewed_at = now(),
           review_note = nullif(btrim(coalesce(p_note,'')), ''), updated_at = now()
     where id = p_deposit_id;
  else
    update public.wallet_deposits
       set status = 'rejected', credited = false,
           reviewed_by = auth.uid()::text, reviewed_at = now(),
           review_note = nullif(btrim(coalesce(p_note,'')), ''), updated_at = now()
     where id = p_deposit_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'status', case when p_approve then 'approved' else 'rejected' end,
    'balance', b
  );
end $$;

-- Permission matrix: read + set (master owner only).
create or replace function public.master_permissions_list()
returns setof public.master_permissions
language sql stable security definer
set search_path = pg_catalog, public, auth, private
as $$
  select * from public.master_permissions
  where private.is_master_owner()
  order by uid, permission;
$$;

create or replace function public.master_permission_set(
  p_uid text,
  p_permission text,
  p_granted boolean
)
returns public.master_permissions
language plpgsql security definer
set search_path = pg_catalog, public, auth, private
as $$
declare r public.master_permissions%rowtype;
begin
  if not private.is_master_owner() then raise exception 'not_authorized'; end if;
  insert into public.master_permissions (uid, permission, granted, granted_by)
  values (p_uid, btrim(p_permission), coalesce(p_granted, true), auth.uid()::text)
  on conflict (uid, permission)
  do update set granted = excluded.granted, granted_by = excluded.granted_by, updated_at = now()
  returning * into r;
  return r;
end $$;

-- Does the caller hold a specific master permission? A master owner holds every
-- permission by default; an explicit granted=false row revokes one.
create or replace function public.has_master_permission(p_permission text)
returns boolean
language sql stable security definer
set search_path = pg_catalog, public, auth, private
as $$
  select private.is_master_owner()
     and coalesce((
       select mp.granted from public.master_permissions mp
       where mp.uid = auth.uid()::text and mp.permission = p_permission
     ), true);
$$;

-- Grants: authenticated callers only.
revoke all on function public.wallet_deposit_create(text, numeric, text, text, uuid) from public, anon;
revoke all on function public.wallet_deposits_list(text, integer) from public, anon;
revoke all on function public.wallet_deposit_decide(uuid, boolean, text) from public, anon;
revoke all on function public.master_permissions_list() from public, anon;
revoke all on function public.master_permission_set(text, text, boolean) from public, anon;
revoke all on function public.has_master_permission(text) from public, anon;

grant execute on function public.wallet_deposit_create(text, numeric, text, text, uuid) to authenticated;
grant execute on function public.wallet_deposits_list(text, integer) to authenticated;
grant execute on function public.wallet_deposit_decide(uuid, boolean, text) to authenticated;
grant execute on function public.master_permissions_list() to authenticated;
grant execute on function public.master_permission_set(text, text, boolean) to authenticated;
grant execute on function public.has_master_permission(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Private storage bucket for deposit receipt images.
-- ---------------------------------------------------------------------------
do $$ begin
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('deposits', 'deposits', false, 10485760,
          array['image/jpeg','image/png','image/webp','application/pdf'])
  on conflict (id) do nothing;
end $$;

drop policy if exists deposits_read on storage.objects;
create policy deposits_read on storage.objects
  for select to authenticated
  using (bucket_id = 'deposits' and (owner = auth.uid() or private.is_master_owner()));

drop policy if exists deposits_insert on storage.objects;
create policy deposits_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'deposits' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists deposits_delete on storage.objects;
create policy deposits_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'deposits' and (owner = auth.uid() or private.is_master_owner()));
