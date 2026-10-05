-- `login_events` only had a staff SELECT policy, so the client's post-login
-- insert (AuthService._recordLoginEvent) was rejected with 42501 and silently
-- swallowed. Add an insert policy scoped to the caller's own uid so login
-- auditing works for every authenticated user without exposing other rows.

drop policy if exists login_events_self_insert on public.login_events;
create policy login_events_self_insert on public.login_events
  for insert to authenticated
  with check (uid = public.current_user_uid());
