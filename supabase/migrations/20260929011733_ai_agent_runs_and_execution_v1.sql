-- Production migration already applied as 20260929011733_ai_agent_runs_and_execution_v1.

create table if not exists public.ai_agent_runs (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.ai_tasks(id) on delete cascade,
  agent_id uuid not null references public.ai_agents(id) on delete restrict,
  provider text not null,
  status text not null default 'queued' check (status in ('queued','running','succeeded','failed','blocked','cancelled')),
  attempt integer not null default 1 check (attempt > 0),
  external_run_id text,
  conversation_id text,
  repository text,
  branch text,
  prompt text not null default '',
  result jsonb not null default '{}'::jsonb,
  error text,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (task_id, attempt)
);

create index if not exists ai_agent_runs_task_created_idx on public.ai_agent_runs (task_id, created_at desc);
create index if not exists ai_agent_runs_status_created_idx on public.ai_agent_runs (status, created_at desc);
alter table public.ai_agent_runs enable row level security;

drop policy if exists ai_agent_runs_staff_read on public.ai_agent_runs;
create policy ai_agent_runs_staff_read on public.ai_agent_runs
  for select to authenticated using ((select private.is_platform_staff()));

revoke all on public.ai_agent_runs from anon, authenticated;

create or replace function public.claim_ai_task_for_execution(
  p_agent_id uuid, p_provider text,
  p_repository text default 'safwt771754091s-crypto/alfaeq_yemen_new',
  p_branch text default 'main'
)
returns table (run_id uuid, task_id uuid, agent_id uuid, attempt integer, title text, description text, priority text, metadata jsonb)
language plpgsql security definer set search_path = public, private
as $$
declare
  v_task public.ai_tasks%rowtype;
  v_agent public.ai_agents%rowtype;
  v_run_id uuid;
  v_attempt integer;
begin
  if not has_function_privilege(current_user, 'public.claim_ai_task_for_execution(uuid,text,text,text)', 'EXECUTE') then
    raise exception 'executor_not_authorized';
  end if;

  select * into v_agent from public.ai_agents
  where id = p_agent_id and status in ('idle','active') for update;
  if not found then raise exception 'agent_not_available'; end if;

  if v_agent.budget_monthly_cents > 0 and v_agent.spend_monthly_cents >= v_agent.budget_monthly_cents then
    update public.ai_agents set status='paused', updated_at=now() where id=v_agent.id;
    raise exception 'agent_budget_exhausted';
  end if;

  select * into v_task from public.ai_tasks
  where status='todo' and (assignee_id is null or assignee_id=p_agent_id)
  order by case priority when 'urgent' then 1 when 'high' then 2 when 'normal' then 3 else 4 end, created_at
  for update skip locked limit 1;
  if not found then return; end if;

  select coalesce(max(r.attempt),0)+1 into v_attempt from public.ai_agent_runs r where r.task_id=v_task.id;

  update public.ai_tasks set status='in_progress', assignee_id=p_agent_id,
    checkout_token=gen_random_uuid(), checked_out_at=now(), updated_at=now()
  where id=v_task.id;

  update public.ai_agents set status='running', updated_at=now(), last_heartbeat_at=now()
  where id=p_agent_id;

  insert into public.ai_agent_runs (task_id, agent_id, provider, status, attempt, repository, branch, prompt, started_at)
  values (v_task.id, p_agent_id, p_provider, 'running', v_attempt, p_repository, p_branch,
          concat(v_task.title, E'\n\n', v_task.description), now())
  returning id into v_run_id;

  return query select v_run_id, v_task.id, p_agent_id, v_attempt,
    v_task.title, v_task.description, v_task.priority, v_task.metadata;
end;
$$;

create or replace function public.complete_ai_agent_run(
  p_run_id uuid, p_status text,
  p_result jsonb default '{}'::jsonb, p_error text default null,
  p_external_run_id text default null, p_conversation_id text default null
)
returns public.ai_agent_runs
language plpgsql security definer set search_path = public, private
as $$
declare
  v_run public.ai_agent_runs%rowtype;
  v_task public.ai_tasks%rowtype;
  v_agent public.ai_agents%rowtype;
begin
  if p_status not in ('succeeded','failed','blocked','cancelled') then raise exception 'invalid_run_status'; end if;
  if not has_function_privilege(current_user, 'public.complete_ai_agent_run(uuid,text,jsonb,text)', 'EXECUTE') then
    raise exception 'executor_not_authorized';
  end if;

  select * into v_run from public.ai_agent_runs where id=p_run_id for update;
  if not found then raise exception 'run_not_found'; end if;

  update public.ai_agent_runs set status=p_status, result=coalesce(p_result,'{}'::jsonb),
    error=p_error, external_run_id=coalesce(p_external_run_id, external_run_id),
    conversation_id=coalesce(p_conversation_id, conversation_id), completed_at=now(), updated_at=now()
  where id=p_run_id returning * into v_run;

  select * into v_task from public.ai_tasks where id=v_run.task_id for update;
  select * into v_agent from public.ai_agents where id=v_run.agent_id for update;

  update public.ai_tasks set status=case
    when p_status='succeeded' then 'done'
    when p_status='blocked' then 'blocked'
    when p_status='cancelled' then 'cancelled'
    else case when v_run.attempt < 3 then 'todo' else 'blocked' end
  end, updated_at=now() where id=v_task.id;

  update public.ai_agents set status=case when p_status='failed' then 'error' else 'idle' end,
    updated_at=now(), last_heartbeat_at=now() where id=v_agent.id;

  return v_run;
end;
$$;

revoke all on function public.claim_ai_task_for_execution(uuid,text,text,text) from public, anon, authenticated;
revoke all on function public.complete_ai_agent_run(uuid,text,jsonb,text,text,text) from public, anon, authenticated;
grant execute on function public.claim_ai_task_for_execution(uuid,text,text,text) to service_role;
grant execute on function public.complete_ai_agent_run(uuid,text,jsonb,text,text,text) to service_role;
