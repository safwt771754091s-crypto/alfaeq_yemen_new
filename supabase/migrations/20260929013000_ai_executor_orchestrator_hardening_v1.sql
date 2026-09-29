-- AI executor orchestration hardening.
-- The original ai_agent_runs migration was already applied before its
-- conversation/external-run parameters were added to the repository file.
-- This additive migration updates the live production functions safely.

create or replace function public.complete_ai_agent_run(
  p_run_id uuid,
  p_status text,
  p_result jsonb default '{}'::jsonb,
  p_error text default null,
  p_external_run_id text default null,
  p_conversation_id text default null
)
returns public.ai_agent_runs
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_run public.ai_agent_runs%rowtype;
  v_task public.ai_tasks%rowtype;
  v_agent public.ai_agents%rowtype;
begin
  if p_status not in ('succeeded','failed','blocked','cancelled') then
    raise exception 'invalid_run_status';
  end if;

  if not has_function_privilege(
    current_user,
    'public.complete_ai_agent_run(uuid,text,jsonb,text)',
    'EXECUTE'
  ) then
    raise exception 'executor_not_authorized';
  end if;

  select * into v_run from public.ai_agent_runs where id = p_run_id for update;
  if not found then raise exception 'run_not_found'; end if;

  update public.ai_agent_runs
  set status = p_status,
      result = coalesce(p_result, '{}'::jsonb),
      error = p_error,
      external_run_id = coalesce(p_external_run_id, external_run_id),
      conversation_id = coalesce(p_conversation_id, conversation_id),
      completed_at = now(),
      updated_at = now()
  where id = p_run_id
  returning * into v_run;

  select * into v_task from public.ai_tasks where id = v_run.task_id for update;
  select * into v_agent from public.ai_agents where id = v_run.agent_id for update;

  update public.ai_tasks
  set status = case
    when p_status = 'succeeded' then 'done'
    when p_status = 'blocked' then 'blocked'
    when p_status = 'cancelled' then 'cancelled'
    else case when v_run.attempt < 3 then 'todo' else 'blocked' end
  end,
  updated_at = now()
  where id = v_task.id;

  update public.ai_agents
  set status = case
    when p_status = 'failed' and v_run.attempt >= 3 then 'error'
    else 'idle'
  end,
  updated_at = now(),
  last_heartbeat_at = now()
  where id = v_agent.id;

  return v_run;
end;
$$;

create or replace function public.complete_ai_agent_run(
  p_run_id uuid,
  p_status text,
  p_result jsonb default '{}'::jsonb,
  p_error text default null
)
returns public.ai_agent_runs
language plpgsql
security definer
set search_path = public, private
as $$
begin
  return public.complete_ai_agent_run(
    p_run_id, p_status, p_result, p_error, null, null
  );
end;
$$;

create or replace function public.heartbeat_ai_agent_run(p_run_id uuid)
returns public.ai_agent_runs
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_run public.ai_agent_runs%rowtype;
begin
  if not has_function_privilege(
    current_user,
    'public.heartbeat_ai_agent_run(uuid)',
    'EXECUTE'
  ) then
    raise exception 'executor_not_authorized';
  end if;

  update public.ai_agent_runs
  set updated_at = now()
  where id = p_run_id and status in ('queued','running')
  returning * into v_run;

  if not found then raise exception 'active_run_not_found'; end if;

  update public.ai_agents
  set last_heartbeat_at = now(), updated_at = now()
  where id = v_run.agent_id;

  return v_run;
end;
$$;

create or replace function public.reconcile_stale_ai_agent_runs(
  p_stale_after interval default interval '20 minutes'
)
returns table(run_id uuid, previous_status text, new_status text, attempt integer)
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_run public.ai_agent_runs%rowtype;
  v_completed public.ai_agent_runs%rowtype;
begin
  if not has_function_privilege(
    current_user,
    'public.reconcile_stale_ai_agent_runs(interval)',
    'EXECUTE'
  ) then
    raise exception 'executor_not_authorized';
  end if;

  for v_run in
    select r.*
    from public.ai_agent_runs r
    where r.status = 'running'
      and coalesce(r.updated_at, r.started_at, r.created_at)
          < now() - p_stale_after
    order by coalesce(r.updated_at, r.started_at, r.created_at)
    for update skip locked
  loop
    v_completed := public.complete_ai_agent_run(
      v_run.id, 'failed',
      jsonb_build_object(
        'reason', 'stale_run_reconciled',
        'stale_after_seconds', extract(epoch from p_stale_after)::integer
      ),
      'Executor run became stale before terminal provider state was observed.',
      v_run.external_run_id,
      v_run.conversation_id
    );

    return query select v_run.id, v_run.status, v_completed.status, v_completed.attempt;
  end loop;
end;
$$;

revoke all on function public.heartbeat_ai_agent_run(uuid) from public, anon, authenticated;
revoke all on function public.reconcile_stale_ai_agent_runs(interval) from public, anon, authenticated;
revoke all on function public.complete_ai_agent_run(uuid,text,jsonb,text,text,text) from public, anon, authenticated;
revoke all on function public.complete_ai_agent_run(uuid,text,jsonb,text) from public, anon, authenticated;

grant execute on function public.heartbeat_ai_agent_run(uuid) to service_role;
grant execute on function public.reconcile_stale_ai_agent_runs(interval) to service_role;
grant execute on function public.complete_ai_agent_run(uuid,text,jsonb,text,text,text) to service_role;
grant execute on function public.complete_ai_agent_run(uuid,text,jsonb,text) to service_role;
