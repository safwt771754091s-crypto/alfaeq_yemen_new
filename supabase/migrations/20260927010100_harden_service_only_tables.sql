-- Keep privileged operational tables inaccessible to client roles while
-- giving the RLS advisor an explicit policy.
create policy automation_endpoints_service_only on public.automation_endpoints
  for all to authenticated using (false) with check (false);
create policy notification_webhook_secrets_service_only on public.notification_webhook_secrets
  for all to authenticated using (false) with check (false);
create policy settlements_service_only on public.settlements
  for all to authenticated using (false) with check (false);
