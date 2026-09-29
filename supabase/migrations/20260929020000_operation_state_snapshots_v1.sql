-- Production state snapshot / compensation boundary.
-- Architectural pattern adapted from SU_IMD v3: capture real prior state,
-- make the operation idempotent, and retain a reversible audit record.
-- No SU_IMD source code is copied; SU_IMD is GPL-3.0.

create table if not exists public.operation_state_snapshots (
  id uuid primary key default gen_random_uuid(),
  idempotency_key text not null unique,
  operation_type text not null,
  aggregate_type text not null,
  aggregate_id text not null,
  before_state jsonb not null default '{}'::jsonb,
  after_state jsonb,
  status text not null default 'active'
    check (status in ('active','completed','reverted','failed')),
  locked_at timestamptz,
  completed_at timestamptz,
  reverted_at timestamptz,
  error jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists operation_state_snapshots_aggregate_idx
  on public.operation_state_snapshots(aggregate_type, aggregate_id, created_at desc);

create index if not exists operation_state_snapshots_status_idx
  on public.operation_state_snapshots(status, updated_at desc);

alter table public.operation_state_snapshots enable row level security;
revoke all on public.operation_state_snapshots from anon, authenticated;

create or replace function public.begin_operation_snapshot(
  p_idempotency_key text,
  p_operation_type text,
  p_aggregate_type text,
  p_aggregate_id text,
  p_before_state jsonb
) returns table(snapshot_id uuid, acquired boolean, status text)
language plpgsql security definer set search_path=''
as $$
declare v_id uuid; v_status text;
begin
  if current_user <> 'service_role' then raise exception 'service_role_required'; end if;
  if coalesce(btrim(p_idempotency_key),'')='' then raise exception 'idempotency_key_required'; end if;

  insert into public.operation_state_snapshots(
    idempotency_key, operation_type, aggregate_type, aggregate_id,
    before_state, locked_at
  ) values (
    p_idempotency_key, p_operation_type, p_aggregate_type, p_aggregate_id,
    coalesce(p_before_state,'{}'::jsonb), now()
  )
  on conflict (idempotency_key) do nothing
  returning id, status into v_id, v_status;

  if v_id is not null then
    return query select v_id, true, v_status;
    return;
  end if;

  select id, status into v_id, v_status
  from public.operation_state_snapshots
  where idempotency_key=p_idempotency_key
  for update;

  return query select v_id, false, v_status;
end
$$;

create or replace function public.complete_operation_snapshot(
  p_snapshot_id uuid,
  p_after_state jsonb
) returns boolean
language plpgsql security definer set search_path=''
as $$
begin
  if current_user <> 'service_role' then raise exception 'service_role_required'; end if;

  update public.operation_state_snapshots
     set after_state=coalesce(p_after_state,'{}'::jsonb),
         status='completed', completed_at=now(), locked_at=null,
         updated_at=now(), error=null
   where id=p_snapshot_id and status='active';

  return found;
end
$$;

create or replace function public.revert_operation_snapshot(
  p_snapshot_id uuid,
  p_error jsonb default null
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_state jsonb;
begin
  if current_user <> 'service_role' then raise exception 'service_role_required'; end if;

  select before_state into v_state
  from public.operation_state_snapshots
  where id=p_snapshot_id and status in ('active','completed')
  for update;

  if not found then return null; end if;

  update public.operation_state_snapshots
     set status='reverted', reverted_at=now(), locked_at=null,
         updated_at=now(), error=coalesce(p_error,error)
   where id=p_snapshot_id;

  return v_state;
end
$$;

revoke all on function public.begin_operation_snapshot(text,text,text,text,jsonb)
  from public,anon,authenticated;
revoke all on function public.complete_operation_snapshot(uuid,jsonb)
  from public,anon,authenticated;
revoke all on function public.revert_operation_snapshot(uuid,jsonb)
  from public,anon,authenticated;

grant execute on function public.begin_operation_snapshot(text,text,text,text,jsonb)
  to service_role;
grant execute on function public.complete_operation_snapshot(uuid,jsonb)
  to service_role;
grant execute on function public.revert_operation_snapshot(uuid,jsonb)
  to service_role;

comment on table public.operation_state_snapshots is
  'Production compensation ledger: captures real prior state, provides idempotent operation boundaries, and retains reversible audit state.';
