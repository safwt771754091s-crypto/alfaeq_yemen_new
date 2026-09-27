-- Production owner controls: merchant catalog management and secure wallet provisioning.
drop policy if exists products_owner_update on public.products;
create policy products_owner_update on public.products
for update to authenticated
using (
  owner_id = current_user_uid()
  or exists (
    select 1 from public.stores s
    where s.id = products.store_id
      and s.owner_id = current_user_uid()
  )
  or (select private.is_platform_staff())
)
with check (
  owner_id = current_user_uid()
  or exists (
    select 1 from public.stores s
    where s.id = products.store_id
      and s.owner_id = current_user_uid()
  )
  or (select private.is_platform_staff())
);

create or replace function public.ensure_my_wallet(
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
begin
  v_uid := auth.uid()::text;
  if v_uid is null then
    raise exception 'authentication required';
  end if;

  select id into v_account_id
  from public.platform_accounts
  where owner_uid = v_uid
    and account_type = p_account_type
    and status = 'active'
  order by created_at
  limit 1;

  if v_account_id is null then
    v_account_id := 'acct-' || v_uid || '-' || lower(p_account_type);
    insert into public.platform_accounts(
      id, account_type, owner_uid, display_name, status, default_currency, metadata
    )
    values(
      v_account_id, p_account_type, v_uid, coalesce(p_account_type,'customer'),
      'active', upper(coalesce(p_currency,'YER')), '{}'::jsonb
    )
    on conflict (id) do nothing;
  end if;

  insert into public.wallets(uid,currency,status,available_balance,metadata,account_id,account_type,owner_uid)
  values(v_uid,upper(coalesce(p_currency,'YER')),'active',0,'{}'::jsonb,v_account_id,p_account_type,v_uid)
  on conflict (uid) do update
    set account_id = coalesce(public.wallets.account_id, excluded.account_id),
        account_type = coalesce(public.wallets.account_type, excluded.account_type),
        owner_uid = coalesce(public.wallets.owner_uid, excluded.owner_uid),
        updated_at = now()
  returning * into v_wallet;

  return v_wallet;
end;
$$;

revoke all on function public.ensure_my_wallet(text,text) from public;
grant execute on function public.ensure_my_wallet(text,text) to authenticated;

drop policy if exists wallets_self_insert on public.wallets;
create policy wallets_self_insert on public.wallets
for insert to authenticated
with check (
  uid = current_user_uid()
  or (select private.is_platform_staff())
);

drop policy if exists wallets_staff_update on public.wallets;
create policy wallets_staff_update on public.wallets
for update to authenticated
using ((select private.is_platform_staff()))
with check ((select private.is_platform_staff()));

drop policy if exists wallets_staff_select on public.wallets;
create policy wallets_staff_select on public.wallets
for select to authenticated
using (uid = current_user_uid() or (select private.is_platform_staff()));
