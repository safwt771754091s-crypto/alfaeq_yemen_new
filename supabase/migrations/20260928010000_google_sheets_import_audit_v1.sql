-- Durable audit trail for spreadsheet-driven catalog/profile imports.
create table if not exists public.automation_import_jobs (
  id uuid primary key,
  source text not null check (source in ('google_sheets','xlsx','csv','api')),
  entity text not null check (entity in ('product','customer')),
  status text not null check (status in ('running','completed','completed_with_errors','failed')),
  rows_received integer not null default 0,
  rows_applied integer not null default 0,
  rows_rejected integer not null default 0,
  errors jsonb not null default '[]'::jsonb,
  dry_run boolean not null default false,
  created_at timestamptz not null default now(),
  completed_at timestamptz not null default now()
);

alter table public.automation_import_jobs enable row level security;

drop policy if exists automation_import_jobs_staff_select on public.automation_import_jobs;
create policy automation_import_jobs_staff_select
on public.automation_import_jobs
for select to authenticated
using ((select private.is_platform_staff()));

revoke all on public.automation_import_jobs from anon, authenticated;
grant select on public.automation_import_jobs to authenticated;

create index if not exists automation_import_jobs_created_idx
  on public.automation_import_jobs(created_at desc);

comment on table public.automation_import_jobs is
  'Audit trail for privileged Google Sheets/catalog/profile imports. Inventory stock is intentionally excluded from catalog sync.';
