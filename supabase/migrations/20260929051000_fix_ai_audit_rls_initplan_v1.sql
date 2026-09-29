-- Production security/performance gate applied to alfaeq_yemen_prod on 2026-09-29.
drop policy if exists ai_jev_decisions_service_only on public.ai_jev_decisions;
create policy ai_jev_decisions_service_only on public.ai_jev_decisions
  for all to service_role using (true) with check (true);

drop policy if exists operation_state_snapshots_service_only on public.operation_state_snapshots;
create policy operation_state_snapshots_service_only on public.operation_state_snapshots
  for all to service_role using (true) with check (true);

drop policy if exists ai_tool_audit_logs_staff_read on public.ai_tool_audit_logs;
create policy ai_tool_audit_logs_staff_read on public.ai_tool_audit_logs
for select to authenticated
using (actor_uid = (select auth.uid()) or (select private.is_platform_staff()));

create index if not exists ai_agent_runs_agent_id_idx on public.ai_agent_runs(agent_id);
create index if not exists chat_members_user_id_idx on public.chat_members(user_id);
create index if not exists chat_messages_sender_id_idx on public.chat_messages(sender_id);
