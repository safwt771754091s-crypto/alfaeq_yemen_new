-- Harden wallet provisioning without breaking the existing RPC name.
-- The privileged implementation lives in the private schema; the public
-- wrapper is SECURITY INVOKER and remains callable only by authenticated users.

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
begin
  v_uid := auth.uid()::text;
  if v_uid is null then
    raise exception 'authentication required';
  end if;

  if coalesce(p_account_type, '') not in ('customer','merchant','driver','platform') then
    raise exception 'invalid account type';
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

  insert into public.wallets(
    uid,currency,status,available_balance,metadata,account_id,account_type,owner_uid
  )
  values(
    v_uid,upper(coalesce(p_currency,'YER')),'active',0,'{}'::jsonb,
    v_account_id,p_account_type,v_uid
  )
  on conflict (uid) do update
    set account_id = coalesce(public.wallets.account_id, excluded.account_id),
        account_type = coalesce(public.wallets.account_type, excluded.account_type),
        owner_uid = coalesce(public.wallets.owner_uid, excluded.owner_uid),
        updated_at = now()
  returning * into v_wallet;

  return v_wallet;
end;
$$;

revoke all on function private.ensure_my_wallet_impl(text,text) from public;
revoke all on function private.ensure_my_wallet_impl(text,text) from anon, authenticated;

create or replace function public.ensure_my_wallet(
  p_currency text default 'YER',
  p_account_type text default 'customer'
)
returns public.wallets
language plpgsql
security invoker
set search_path = pg_catalog, public, auth, private
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;
  return private.ensure_my_wallet_impl(p_currency, p_account_type);
end;
$$;

revoke all on function public.ensure_my_wallet(text,text) from public, anon;
grant execute on function public.ensure_my_wallet(text,text) to authenticated;

-- Consolidate overlapping SELECT policies.
drop policy if exists wallets_self_select on public.wallets;
drop policy if exists wallets_staff_select on public.wallets;

create policy wallets_select on public.wallets
for select to authenticated
using (
  uid = current_user_uid()
  or (select private.is_platform_staff())
);
