-- Multi-store: stores created through a merchant invite had no section, so
-- `CatalogService.approvedStores(sectionId)` never returned them and the
-- customer "المتاجر" tab stayed empty even after the owner approved them.
--
-- Additive: adds an optional section to invites, uses it when the store is
-- created, defaults legacy/NULL stores to the first section (`markets`).

alter table public.merchant_invites
  add column if not exists section_id text;

create or replace function private.redeem_merchant_invite_internal(p_token text)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  u text;
  v_invite public.merchant_invites%rowtype;
  v_hash text;
  v_store_id text;
  v_section text;
begin
  if auth.uid() is null or p_token is null or length(trim(p_token)) = 0 then
    raise exception 'invalid invite';
  end if;
  u := auth.uid()::text;

  v_hash := encode(extensions.digest(trim(p_token), 'sha256'), 'hex');

  select * into v_invite
  from public.merchant_invites
  where token_hash = v_hash
    and status = 'active'
    and (expires_at is null or expires_at > now())
    and used_at is null
  for update;

  if not found then
    raise exception 'invite not found or already used';
  end if;

  v_section := nullif(trim(coalesce(v_invite.section_id, '')), '');
  if v_section is null then
    v_section := 'markets';
  end if;

  update public.merchant_invites
  set status = 'used', used_by = u, used_at = now()
  where token_hash = v_hash;

  v_store_id := 'store-' || u;
  insert into public.stores(id, owner_id, name, status, section_id, metadata)
  values (
    v_store_id, u,
    coalesce(nullif(trim(v_invite.label), ''), 'متجر جديد'),
    'pending', v_section, '{}'::jsonb
  )
  on conflict (id) do update
    set owner_id = excluded.owner_id,
        status = 'pending',
        section_id = coalesce(excluded.section_id, public.stores.section_id),
        updated_at = now();

  perform set_config('app.allow_merchant_promotion', 'on', true);
  update public.users set role = 'merchant', updated_at = now()
  where uid = u and role not in ('owner', 'admin', 'developer');
  return true;
end
$function$;

revoke all on function private.redeem_merchant_invite_internal(text) from public, anon;
grant execute on function private.redeem_merchant_invite_internal(text) to authenticated;

-- Make existing stores reachable in the customer store listing.
update public.stores set section_id = 'markets', updated_at = now()
where section_id is null;
