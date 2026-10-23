-- Fix: owner/admin role changes never persisted, and public site updates
-- could never be published.
--
-- 1) private.protect_user_privileges() only recognised a caller as staff when
--    the JWT carried an app_role/admin/owner/developer claim. The admin-users
--    Edge Function calls it with the SERVICE ROLE key, so auth.jwt() is null
--    and every set_role update was silently reverted to the previous role --
--    merchants/drivers could never be granted their role. Treat a service_role
--    caller as fully trusted (it already bypasses RLS and is server-only).
--
-- 2) public_site_updates had a SELECT policy but no write policy, so the
--    "آخر تحديثات الفائق" section could never be populated from the admin app.
--    Add staff-only write policies.

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
  is_staff := auth.role() = 'service_role'
    or coalesce((auth.jwt()->>'app_role') in ('admin','owner','developer'), false)
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

-- Staff-only write access for public site updates.
drop policy if exists site_updates_staff_insert on public.public_site_updates;
create policy site_updates_staff_insert on public.public_site_updates
  for insert to authenticated
  with check (private.is_platform_staff());

drop policy if exists site_updates_staff_update on public.public_site_updates;
create policy site_updates_staff_update on public.public_site_updates
  for update to authenticated
  using (private.is_platform_staff())
  with check (private.is_platform_staff());

drop policy if exists site_updates_staff_delete on public.public_site_updates;
create policy site_updates_staff_delete on public.public_site_updates
  for delete to authenticated
  using (private.is_platform_staff());

-- Seed a first welcome update so the section is never empty on a fresh install.
insert into public.public_site_updates (id, title, summary, status, published_at, sort_order)
values (
  'welcome-alfaeq',
  'مرحباً بكم في الفائق يمن',
  'منصة تجارية واحدة: تسوّق، تابع طلباتك، وتواصل مع التجار والمندوبين.',
  'published',
  now(),
  0
)
on conflict (id) do nothing;

-- 3) ensure_driver_profile() only trusted the JWT claim, but admin-users
--    persists the role in public.users (not app_metadata), so a freshly
--    promoted driver hit 'driver_role_required' until their token refreshed.
--    Accept the persisted role as well.
create or replace function private.ensure_driver_profile()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare v_uid text := auth.uid()::text;
begin
 if v_uid is null then raise exception 'unauthenticated'; end if;
 if not (
   coalesce(auth.jwt()->>'app_role','') in ('driver','admin','owner','developer')
   or coalesce((auth.jwt()->>'admin')::boolean,false)
   or coalesce((auth.jwt()->>'owner')::boolean,false)
   or coalesce((auth.jwt()->>'developer')::boolean,false)
   or exists (
     select 1 from public.users u
     where u.uid = v_uid and u.role in ('driver','admin','owner','developer')
   )
 ) then
   raise exception 'driver_role_required';
 end if;
 insert into public.drivers(uid,approved,is_online,active_order_count)
 values(v_uid,false,false,0) on conflict(uid) do nothing;
 return jsonb_build_object('ok',true,'uid',v_uid);
end;
$function$;
