-- Production-only merchant review audit trail.
create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_uid text not null,
  email text,
  action text not null,
  result text not null default 'success',
  source text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.audit_logs enable row level security;

drop policy if exists "audit_logs_staff_read" on public.audit_logs;
create policy "audit_logs_staff_read"
on public.audit_logs for select to authenticated
using (
  coalesce(auth.jwt()->>'app_role','') in ('admin','owner','developer')
  or coalesce((auth.jwt()->>'admin')::boolean,false)
  or coalesce((auth.jwt()->>'owner')::boolean,false)
  or coalesce((auth.jwt()->>'developer')::boolean,false)
);

drop policy if exists "audit_logs_staff_insert" on public.audit_logs;
create policy "audit_logs_staff_insert"
on public.audit_logs for insert to authenticated
with check (
  actor_uid = auth.uid()::text
  and (
    coalesce(auth.jwt()->>'app_role','') in ('admin','owner','developer')
    or coalesce((auth.jwt()->>'admin')::boolean,false)
    or coalesce((auth.jwt()->>'owner')::boolean,false)
    or coalesce((auth.jwt()->>'developer')::boolean,false)
  )
);

do $$
begin
  if to_regclass('public.stores') is not null then
    alter table public.stores add column if not exists reviewed_by text;
    alter table public.stores add column if not exists reviewed_at timestamptz;
  end if;
end $$;
