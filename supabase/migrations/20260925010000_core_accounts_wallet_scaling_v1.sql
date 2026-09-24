-- Core account model: one canonical account can represent a customer, merchant, driver, truck driver, service provider, partner or platform actor.
create table if not exists public.platform_accounts (
  id text primary key,
  account_type text not null check (account_type in (
    'customer','merchant','delivery_driver','truck_driver',
    'service_provider','partner','platform','other'
  )),
  owner_uid text null references public.users(uid) on delete set null,
  display_name text,
  status text not null default 'active' check (status in ('active','suspended','closed','pending')),
  default_currency text not null default 'YER',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.account_members (
  account_id text not null references public.platform_accounts(id) on delete cascade,
  user_id text not null references public.users(uid) on delete cascade,
  member_role text not null default 'member' check (member_role in ('owner','admin','manager','member','finance','dispatcher')),
  status text not null default 'active' check (status in ('active','suspended','removed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (account_id,user_id)
);

alter table public.wallets
  add column if not exists account_id text,
  add column if not exists account_type text,
  add column if not exists owner_uid text;

create unique index if not exists wallets_account_id_uidx
  on public.wallets(account_id) where account_id is not null;

create index if not exists platform_accounts_owner_idx
  on public.platform_accounts(owner_uid, account_type, status);
create index if not exists platform_accounts_type_status_idx
  on public.platform_accounts(account_type, status, created_at desc);
create index if not exists account_members_user_status_idx
  on public.account_members(user_id, status, account_id);
create index if not exists account_members_account_status_idx
  on public.account_members(account_id, status, user_id);
create index if not exists wallets_owner_type_idx
  on public.wallets(owner_uid, account_type, status);
create index if not exists wallet_ledger_account_time_idx
  on public.wallet_ledger(wallet_uid, created_at desc);
create index if not exists wallet_transactions_uid_time_idx
  on public.wallet_transactions(uid, created_at desc);
create index if not exists products_store_section_status_idx
  on public.products(store_id, section_id, status, created_at desc);
create index if not exists products_owner_status_idx
  on public.products(owner_id, status, created_at desc);
create index if not exists stores_owner_status_idx
  on public.stores(owner_id, status, created_at desc);
create index if not exists orders_merchant_status_time_idx
  on public.orders(merchant_id, status, created_at desc);
create index if not exists order_items_product_time_idx
  on public.order_items(product_id, created_at desc);

alter table public.platform_accounts enable row level security;
alter table public.account_members enable row level security;

drop policy if exists platform_accounts_member_select on public.platform_accounts;
create policy platform_accounts_member_select on public.platform_accounts
for select to authenticated
using (
  owner_uid = current_user_uid()
  or exists (
    select 1 from public.account_members m
    where m.account_id = platform_accounts.id
      and m.user_id = current_user_uid()
      and m.status = 'active'
  )
  or (select private.is_platform_staff())
);

drop policy if exists account_members_self_select on public.account_members;
create policy account_members_self_select on public.account_members
for select to authenticated
using (
  user_id = current_user_uid()
  or exists (
    select 1 from public.platform_accounts a
    where a.id = account_members.account_id
      and (a.owner_uid = current_user_uid() or (select private.is_platform_staff()))
  )
);

comment on table public.platform_accounts is 'Canonical business/account entity for customers, merchants, drivers and platform actors.';
comment on table public.account_members is 'Membership and role mapping between platform accounts and users.';
comment on column public.wallets.account_id is 'Stable platform account owning this wallet; legacy uid remains for compatibility.';
