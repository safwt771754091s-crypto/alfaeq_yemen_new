drop policy if exists audit_logs_staff_read on public.audit_logs;
create policy audit_logs_staff_read on public.audit_logs
for select to authenticated
using (
  coalesce((select auth.jwt()->>'app_role'),'') = any(array['admin','owner','developer'])
  or coalesce(((select auth.jwt()->>'admin'))::boolean,false)
  or coalesce(((select auth.jwt()->>'owner'))::boolean,false)
  or coalesce(((select auth.jwt()->>'developer'))::boolean,false)
);

drop policy if exists audit_logs_staff_insert on public.audit_logs;
create policy audit_logs_staff_insert on public.audit_logs
for insert to authenticated
with check (
  actor_uid=(select auth.uid())::text
  and (
    coalesce((select auth.jwt()->>'app_role'),'') = any(array['admin','owner','developer'])
    or coalesce(((select auth.jwt()->>'admin'))::boolean,false)
    or coalesce(((select auth.jwt()->>'owner'))::boolean,false)
    or coalesce(((select auth.jwt()->>'developer'))::boolean,false)
  )
);