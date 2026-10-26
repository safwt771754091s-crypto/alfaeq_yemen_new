-- Self-service applications to become a merchant (تاجر) or a driver (مندوب).
--
-- Before this migration the only way in was an admin-issued invite (merchants)
-- or an admin role change (drivers). Customers had no way to apply. This adds:
--   1) public.merchant_applications / public.driver_applications — one row per
--      application, readable by its owner and by platform staff.
--   2) submit / decide / cancel RPCs. Submission is self-service; approval is
--      staff-only and performs the real side effects (create the store, promote
--      the role, create the driver profile) and notifies the applicant.
--
-- Additive only.

-- ---------------------------------------------------------------------------
-- 0) Make the privilege guard recognise DB-backed staff.
--    protect_user_privileges() previously trusted only JWT claims (plus the
--    service_role key). A DB-backed owner whose token carries no app_role claim
--    could pass is_platform_staff() yet have their role change silently
--    reverted here. Delegate the staff check to the same DB-backed helper.
-- ---------------------------------------------------------------------------
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
    or private.is_platform_staff();

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

-- ---------------------------------------------------------------------------
-- 1) Tables
-- ---------------------------------------------------------------------------
create table if not exists public.merchant_applications (
  id uuid primary key default gen_random_uuid(),
  uid text not null references public.users(uid) on delete cascade,
  applicant_name text not null default '',
  phone text not null,
  email text,
  store_name text not null,
  section_id text,
  city text,
  address text,
  notes text,
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  reviewed_by text,
  reviewed_at timestamptz,
  review_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.driver_applications (
  id uuid primary key default gen_random_uuid(),
  uid text not null references public.users(uid) on delete cascade,
  applicant_name text not null default '',
  phone text not null,
  email text,
  vehicle_type text,
  vehicle_plate text,
  city text,
  notes text,
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  reviewed_by text,
  reviewed_at timestamptz,
  review_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists merchant_applications_uid_idx on public.merchant_applications(uid);
create index if not exists merchant_applications_status_idx on public.merchant_applications(status);
create index if not exists driver_applications_uid_idx on public.driver_applications(uid);
create index if not exists driver_applications_status_idx on public.driver_applications(status);

-- One open application per user (a cancelled/rejected one may be resubmitted).
create unique index if not exists merchant_applications_one_pending_idx
  on public.merchant_applications(uid) where status = 'pending';
create unique index if not exists driver_applications_one_pending_idx
  on public.driver_applications(uid) where status = 'pending';

alter table public.merchant_applications enable row level security;
alter table public.driver_applications enable row level security;

drop policy if exists merchant_applications_select on public.merchant_applications;
create policy merchant_applications_select on public.merchant_applications
  for select to authenticated
  using (uid = auth.uid()::text or private.is_platform_staff());

drop policy if exists merchant_applications_insert on public.merchant_applications;
create policy merchant_applications_insert on public.merchant_applications
  for insert to authenticated
  with check (uid = auth.uid()::text and status = 'pending');

-- Only staff may mutate directly; applicants use the cancel RPC (SECURITY DEFINER).
drop policy if exists merchant_applications_update on public.merchant_applications;
create policy merchant_applications_update on public.merchant_applications
  for update to authenticated
  using (private.is_platform_staff())
  with check (private.is_platform_staff());

drop policy if exists driver_applications_select on public.driver_applications;
create policy driver_applications_select on public.driver_applications
  for select to authenticated
  using (uid = auth.uid()::text or private.is_platform_staff());

drop policy if exists driver_applications_insert on public.driver_applications;
create policy driver_applications_insert on public.driver_applications
  for insert to authenticated
  with check (uid = auth.uid()::text and status = 'pending');

drop policy if exists driver_applications_update on public.driver_applications;
create policy driver_applications_update on public.driver_applications
  for update to authenticated
  using (private.is_platform_staff())
  with check (private.is_platform_staff());

grant select, insert on public.merchant_applications to authenticated;
grant select, insert on public.driver_applications to authenticated;

-- ---------------------------------------------------------------------------
-- 2) Merchant application RPCs
-- ---------------------------------------------------------------------------
create or replace function private.merchant_application_submit(
  p_applicant_name text,
  p_phone text,
  p_store_name text,
  p_section_id text default null,
  p_city text default null,
  p_address text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid text := auth.uid()::text;
  v_role text;
  v_email text;
  v_id uuid;
begin
  if v_uid is null then raise exception 'unauthenticated'; end if;
  if p_store_name is null or btrim(p_store_name) = '' then raise exception 'store_name_required'; end if;
  if p_phone is null or btrim(p_phone) = '' then raise exception 'phone_required'; end if;

  select coalesce(role, 'customer') into v_role from public.users where uid = v_uid;
  if v_role in ('owner','admin','developer','merchant') then
    raise exception 'already_privileged';
  end if;

  if exists (select 1 from public.merchant_applications where uid = v_uid and status = 'pending') then
    raise exception 'application_pending';
  end if;

  v_email := auth.jwt()->>'email';

  insert into public.merchant_applications(
    uid, applicant_name, phone, email, store_name, section_id, city, address, notes
  ) values (
    v_uid, coalesce(nullif(btrim(coalesce(p_applicant_name,'')),''), ''), btrim(p_phone), v_email,
    btrim(p_store_name), nullif(btrim(coalesce(p_section_id,'')),''), nullif(btrim(coalesce(p_city,'')),''),
    nullif(btrim(coalesce(p_address,'')),''), nullif(btrim(coalesce(p_notes,'')),'')
  )
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end
$function$;

create or replace function private.merchant_application_decide(
  p_application_id uuid,
  p_approve boolean,
  p_review_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid text := auth.uid()::text;
  v_app public.merchant_applications%rowtype;
  v_store_id text;
begin
  if not private.is_platform_staff() then raise exception 'not_authorized'; end if;

  select * into v_app from public.merchant_applications where id = p_application_id for update;
  if not found then raise exception 'application_not_found'; end if;
  if v_app.status <> 'pending' then raise exception 'application_not_pending'; end if;

  if p_approve then
    v_store_id := 'store-' || v_app.uid;
    insert into public.stores(id, owner_id, name, status, section_id, phone, address, metadata)
    values (
      v_store_id, v_app.uid, v_app.store_name, 'pending',
      v_app.section_id, v_app.phone, v_app.address,
      jsonb_build_object('source', 'merchant_application', 'application_id', p_application_id)
    )
    on conflict (id) do update
      set owner_id = excluded.owner_id,
          name = excluded.name,
          section_id = coalesce(excluded.section_id, public.stores.section_id),
          phone = coalesce(excluded.phone, public.stores.phone),
          address = coalesce(excluded.address, public.stores.address),
          updated_at = now();

    update public.users set role = 'merchant', updated_at = now()
    where uid = v_app.uid and role not in ('owner','admin','developer');
  end if;

  update public.merchant_applications
  set status = case when p_approve then 'approved' else 'rejected' end,
      reviewed_by = v_uid,
      reviewed_at = now(),
      review_notes = nullif(btrim(coalesce(p_review_notes,'')),''),
      updated_at = now()
  where id = p_application_id;

  perform private.notify_user(
    v_app.uid,
    case when p_approve then 'merchant_application_approved' else 'merchant_application_rejected' end,
    case when p_approve then 'تم اعتماد طلبك كتاجر' else 'طلب المتجر لم يُعتمد' end,
    case when p_approve
      then 'تم اعتماد طلبك كتاجر في الفائق يمن. افتح مركز التاجر لإكمال بيانات متجرك.'
      else coalesce(nullif(btrim(coalesce(p_review_notes,'')),''), 'لم يتم اعتماد طلب المتجر. يمكنك التواصل مع الدعم لمزيد من التفاصيل.')
    end,
    jsonb_build_object('application_id', p_application_id, 'store_id', v_store_id)
  );

  return jsonb_build_object('ok', true, 'status', case when p_approve then 'approved' else 'rejected' end);
end
$function$;

create or replace function private.merchant_application_cancel(p_application_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid text := auth.uid()::text;
begin
  if v_uid is null then raise exception 'unauthenticated'; end if;
  update public.merchant_applications
  set status = 'cancelled', updated_at = now()
  where id = p_application_id and uid = v_uid and status = 'pending';
  if not found then raise exception 'application_not_pending'; end if;
  return jsonb_build_object('ok', true);
end
$function$;

-- ---------------------------------------------------------------------------
-- 3) Driver application RPCs
-- ---------------------------------------------------------------------------
create or replace function private.driver_application_submit(
  p_applicant_name text,
  p_phone text,
  p_vehicle_type text default null,
  p_vehicle_plate text default null,
  p_city text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid text := auth.uid()::text;
  v_role text;
  v_email text;
  v_id uuid;
begin
  if v_uid is null then raise exception 'unauthenticated'; end if;
  if p_phone is null or btrim(p_phone) = '' then raise exception 'phone_required'; end if;

  select coalesce(role, 'customer') into v_role from public.users where uid = v_uid;
  if v_role in ('owner','admin','developer','merchant') then
    raise exception 'already_privileged';
  end if;

  if exists (select 1 from public.driver_applications where uid = v_uid and status = 'pending') then
    raise exception 'application_pending';
  end if;

  v_email := auth.jwt()->>'email';

  insert into public.driver_applications(
    uid, applicant_name, phone, email, vehicle_type, vehicle_plate, city, notes
  ) values (
    v_uid, coalesce(nullif(btrim(coalesce(p_applicant_name,'')),''), ''), btrim(p_phone), v_email,
    nullif(btrim(coalesce(p_vehicle_type,'')),''), nullif(btrim(coalesce(p_vehicle_plate,'')),''),
    nullif(btrim(coalesce(p_city,'')),''), nullif(btrim(coalesce(p_notes,'')),'')
  )
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end
$function$;

create or replace function private.driver_application_decide(
  p_application_id uuid,
  p_approve boolean,
  p_review_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid text := auth.uid()::text;
  v_app public.driver_applications%rowtype;
begin
  if not private.is_platform_staff() then raise exception 'not_authorized'; end if;

  select * into v_app from public.driver_applications where id = p_application_id for update;
  if not found then raise exception 'application_not_found'; end if;
  if v_app.status <> 'pending' then raise exception 'application_not_pending'; end if;

  if p_approve then
    insert into public.drivers(uid, approved, is_online, active_order_count)
    values (v_app.uid, false, false, 0)
    on conflict (uid) do nothing;

    update public.users set role = 'driver', updated_at = now()
    where uid = v_app.uid
      and coalesce(role, 'customer') in ('customer','finance','support');
  end if;

  update public.driver_applications
  set status = case when p_approve then 'approved' else 'rejected' end,
      reviewed_by = v_uid,
      reviewed_at = now(),
      review_notes = nullif(btrim(coalesce(p_review_notes,'')),''),
      updated_at = now()
  where id = p_application_id;

  perform private.notify_user(
    v_app.uid,
    case when p_approve then 'driver_application_approved' else 'driver_application_rejected' end,
    case when p_approve then 'تم اعتماد طلبك كمندوب' else 'طلب المندوب لم يُعتمد' end,
    case when p_approve
      then 'تم اعتماد طلبك كمندوب. سيتم تفعيل حسابك عند اعتمادك في لوحة التوزيع.'
      else coalesce(nullif(btrim(coalesce(p_review_notes,'')),''), 'لم يتم اعتماد طلب المندوب. يمكنك التواصل مع الدعم لمزيد من التفاصيل.')
    end,
    jsonb_build_object('application_id', p_application_id)
  );

  return jsonb_build_object('ok', true, 'status', case when p_approve then 'approved' else 'rejected' end);
end
$function$;

create or replace function private.driver_application_cancel(p_application_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid text := auth.uid()::text;
begin
  if v_uid is null then raise exception 'unauthenticated'; end if;
  update public.driver_applications
  set status = 'cancelled', updated_at = now()
  where id = p_application_id and uid = v_uid and status = 'pending';
  if not found then raise exception 'application_not_pending'; end if;
  return jsonb_build_object('ok', true);
end
$function$;

-- ---------------------------------------------------------------------------
-- 4) Public SECURITY INVOKER wrappers (the app calls these).
-- ---------------------------------------------------------------------------
revoke all on function private.merchant_application_submit(text,text,text,text,text,text,text) from public, anon;
revoke all on function private.merchant_application_decide(uuid,boolean,text) from public, anon;
revoke all on function private.merchant_application_cancel(uuid) from public, anon;
revoke all on function private.driver_application_submit(text,text,text,text,text,text) from public, anon;
revoke all on function private.driver_application_decide(uuid,boolean,text) from public, anon;
revoke all on function private.driver_application_cancel(uuid) from public, anon;

grant execute on function private.merchant_application_submit(text,text,text,text,text,text,text) to authenticated;
grant execute on function private.merchant_application_decide(uuid,boolean,text) to authenticated;
grant execute on function private.merchant_application_cancel(uuid) to authenticated;
grant execute on function private.driver_application_submit(text,text,text,text,text,text) to authenticated;
grant execute on function private.driver_application_decide(uuid,boolean,text) to authenticated;
grant execute on function private.driver_application_cancel(uuid) to authenticated;

create or replace function public.merchant_application_submit(
  p_applicant_name text,
  p_phone text,
  p_store_name text,
  p_section_id text default null,
  p_city text default null,
  p_address text default null,
  p_notes text default null
)
returns jsonb language sql security invoker set search_path to ''
as $$ select private.merchant_application_submit(p_applicant_name, p_phone, p_store_name, p_section_id, p_city, p_address, p_notes) $$;

create or replace function public.merchant_application_decide(
  p_application_id uuid,
  p_approve boolean,
  p_review_notes text default null
)
returns jsonb language sql security invoker set search_path to ''
as $$ select private.merchant_application_decide(p_application_id, p_approve, p_review_notes) $$;

create or replace function public.merchant_application_cancel(p_application_id uuid)
returns jsonb language sql security invoker set search_path to ''
as $$ select private.merchant_application_cancel(p_application_id) $$;

create or replace function public.driver_application_submit(
  p_applicant_name text,
  p_phone text,
  p_vehicle_type text default null,
  p_vehicle_plate text default null,
  p_city text default null,
  p_notes text default null
)
returns jsonb language sql security invoker set search_path to ''
as $$ select private.driver_application_submit(p_applicant_name, p_phone, p_vehicle_type, p_vehicle_plate, p_city, p_notes) $$;

create or replace function public.driver_application_decide(
  p_application_id uuid,
  p_approve boolean,
  p_review_notes text default null
)
returns jsonb language sql security invoker set search_path to ''
as $$ select private.driver_application_decide(p_application_id, p_approve, p_review_notes) $$;

create or replace function public.driver_application_cancel(p_application_id uuid)
returns jsonb language sql security invoker set search_path to ''
as $$ select private.driver_application_cancel(p_application_id) $$;

revoke all on function public.merchant_application_submit(text,text,text,text,text,text,text) from public, anon;
revoke all on function public.merchant_application_decide(uuid,boolean,text) from public, anon;
revoke all on function public.merchant_application_cancel(uuid) from public, anon;
revoke all on function public.driver_application_submit(text,text,text,text,text,text) from public, anon;
revoke all on function public.driver_application_decide(uuid,boolean,text) from public, anon;
revoke all on function public.driver_application_cancel(uuid) from public, anon;

grant execute on function public.merchant_application_submit(text,text,text,text,text,text,text) to authenticated;
grant execute on function public.merchant_application_decide(uuid,boolean,text) to authenticated;
grant execute on function public.merchant_application_cancel(uuid) to authenticated;
grant execute on function public.driver_application_submit(text,text,text,text,text,text) to authenticated;
grant execute on function public.driver_application_decide(uuid,boolean,text) to authenticated;
grant execute on function public.driver_application_cancel(uuid) to authenticated;
