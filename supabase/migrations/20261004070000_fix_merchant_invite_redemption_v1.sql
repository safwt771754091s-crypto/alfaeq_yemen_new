-- Fix merchant invite redemption, which always failed with
-- 42703 column "invite_token" does not exist.
--
-- Invite tokens are minted by the create-merchant-invite edge function and
-- stored SHA-256-hashed (hex) in public.merchant_invites, but redemption looked
-- up a stores.invite_token column that never existed, so every redemption
-- raised. It also never created a store for the invitee.
--
-- Redemption now: hashes the presented token, validates an active/unexpired/
-- unused invite, marks it used, creates a pending store owned by the caller,
-- and promotes the caller to merchant.

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

  update public.merchant_invites
  set status = 'used', used_by = u, used_at = now()
  where token_hash = v_hash;

  v_store_id := 'store-' || u;
  insert into public.stores(id, owner_id, name, status, metadata)
  values (
    v_store_id, u,
    coalesce(nullif(trim(v_invite.label), ''), 'متجر جديد'),
    'pending', '{}'::jsonb
  )
  on conflict (id) do update
    set owner_id = excluded.owner_id,
        status = 'pending',
        updated_at = now();

  perform set_config('app.allow_merchant_promotion', 'on', true);
  update public.users set role = 'merchant', updated_at = now()
  where uid = u and role not in ('owner', 'admin', 'developer');
  return true;
end
$function$;

revoke all on function private.redeem_merchant_invite_internal(text) from public, anon;
grant execute on function private.redeem_merchant_invite_internal(text) to authenticated;

-- protect_user_privileges reverts role for non-staff callers, so a verified
-- invite redemption must be allowed to promote the caller to 'merchant' only.
-- The flag is set transaction-locally by the redemption function; admin, owner,
-- developer, and access_level stay protected unconditionally.
create or replace function private.protect_user_privileges()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  is_staff boolean;
  allow_merchant boolean;
begin
  is_staff := coalesce((auth.jwt()->>'app_role') in ('admin','owner','developer'), false)
    or coalesce((auth.jwt()->>'admin')::boolean, false)
    or coalesce((auth.jwt()->>'owner')::boolean, false)
    or coalesce((auth.jwt()->>'developer')::boolean, false)
    or coalesce((auth.jwt()->'app_metadata'->>'app_role') in ('admin','owner','developer'), false)
    or coalesce((auth.jwt()->'app_metadata'->>'admin')::boolean, false)
    or coalesce((auth.jwt()->'app_metadata'->>'owner')::boolean, false)
    or coalesce((auth.jwt()->'app_metadata'->>'developer')::boolean, false);

  allow_merchant := coalesce(current_setting('app.allow_merchant_promotion', true), '') = 'on'
    and new.role = 'merchant';

  if not is_staff then
    if not allow_merchant then
      new.role := old.role;
    end if;
    new.admin := old.admin;
    new.owner := old.owner;
    new.developer := old.developer;
    new.access_level := old.access_level;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

revoke all on function private.protect_user_privileges() from public;

