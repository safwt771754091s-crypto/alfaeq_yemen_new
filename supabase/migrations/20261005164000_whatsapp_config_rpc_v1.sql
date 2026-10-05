-- WhatsApp configuration accessors (Alfaeq Yemen).
--
-- Secrets live in Supabase Vault. `set_whatsapp_config` lets platform staff
-- provision them from the app (or SQL); `get_whatsapp_config` returns only the
-- non-sending values the webhook needs (verify token, app secret). The access
-- token and phone number id stay server-side and are never returned.
--
-- Additive only.

create or replace function public.set_whatsapp_config(
  p_access_token text default null,
  p_phone_number_id text default null,
  p_verify_token text default null,
  p_app_secret text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, vault, private
as $$
declare
  v_name text;
  v_value text;
  v_updated text[] := '{}';
  v_names text[] := array['WHATSAPP_ACCESS_TOKEN', 'WHATSAPP_PHONE_NUMBER_ID', 'WHATSAPP_VERIFY_TOKEN', 'WHATSAPP_APP_SECRET'];
  v_values text[] := array[p_access_token, p_phone_number_id, p_verify_token, p_app_secret];
  i integer;
begin
  if not (private.is_platform_staff() or auth.role() = 'service_role') then
    raise exception 'not_authorized';
  end if;

  for i in 1..array_length(v_names, 1) loop
    v_name := v_names[i];
    v_value := v_values[i];
    if v_value is null or v_value = '' then
      continue;
    end if;
    if exists (select 1 from vault.secrets where name = v_name) then
      perform vault.update_secret((select id from vault.secrets where name = v_name), v_value);
    else
      perform vault.create_secret(v_value, v_name);
    end if;
    v_updated := array_append(v_updated, v_name);
  end loop;

  return jsonb_build_object(
    'ok', true,
    'updated', to_jsonb(v_updated),
    'configured', private.whatsapp_configured()
  );
end;
$$;

revoke all on function public.set_whatsapp_config(text, text, text, text) from public, anon;
grant execute on function public.set_whatsapp_config(text, text, text, text) to authenticated, service_role;

create or replace function public.get_whatsapp_config()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, vault, private
as $$
begin
  if not (private.is_platform_staff() or auth.role() = 'service_role') then
    raise exception 'not_authorized';
  end if;
  return jsonb_build_object(
    'verify_token', private.whatsapp_secret('WHATSAPP_VERIFY_TOKEN'),
    'app_secret', private.whatsapp_secret('WHATSAPP_APP_SECRET'),
    'configured', private.whatsapp_configured()
  );
end;
$$;

revoke all on function public.get_whatsapp_config() from public, anon;
grant execute on function public.get_whatsapp_config() to authenticated, service_role;
