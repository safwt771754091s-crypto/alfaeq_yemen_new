-- Keep automation delivery on the durable queue + automation-worker path only.
-- Direct Postgres -> n8n triggers caused duplicate delivery for content events.
drop trigger if exists promotions_n8n_dispatch on public.promotions;
drop trigger if exists site_updates_n8n_dispatch on public.public_site_updates;

-- This legacy helper is no longer part of the delivery path.
revoke execute on function public.dispatch_automation_event() from public, anon, authenticated;
