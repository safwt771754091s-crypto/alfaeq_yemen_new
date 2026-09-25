-- Reduce overlapping permissive RLS policies while preserving public read and staff write access.
-- Also use initplan-safe wrappers for audit log authorization.

drop policy if exists audit_logs_staff_select on public.audit_logs;

drop policy if exists audit_logs_staff_read on public.audit_logs;
create policy audit_logs_staff_read
on public.audit_logs
for select to authenticated
using ((select private.is_platform_staff()));

drop policy if exists audit_logs_staff_insert on public.audit_logs;
create policy audit_logs_staff_insert
on public.audit_logs
for insert to authenticated
with check (
  actor_uid = (select auth.uid())::text
  and (select private.is_platform_staff())
);

drop policy if exists payment_providers_public_select on public.payment_providers;
create policy payment_providers_public_select
on public.payment_providers
for select to anon, authenticated
using (enabled = true);

drop policy if exists payment_providers_staff_all on public.payment_providers;
create policy payment_providers_staff_insert on public.payment_providers
for insert to authenticated
with check ((select private.is_platform_staff()));
create policy payment_providers_staff_update on public.payment_providers
for update to authenticated
using ((select private.is_platform_staff()))
with check ((select private.is_platform_staff()));
create policy payment_providers_staff_delete on public.payment_providers
for delete to authenticated
using ((select private.is_platform_staff()));

drop policy if exists sections_public_select on public.sections;
create policy sections_public_select
on public.sections
for select to anon, authenticated
using (status = 'active');

drop policy if exists sections_staff_all on public.sections;
create policy sections_staff_insert on public.sections
for insert to authenticated
with check ((select private.is_platform_staff()));
create policy sections_staff_update on public.sections
for update to authenticated
using ((select private.is_platform_staff()))
with check ((select private.is_platform_staff()));
create policy sections_staff_delete on public.sections
for delete to authenticated
using ((select private.is_platform_staff()));

drop policy if exists whatsapp_connections_owner_select on public.whatsapp_connections;
