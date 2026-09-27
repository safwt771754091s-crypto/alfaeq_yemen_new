-- Accept the standard Supabase app_metadata JWT location as well as
-- legacy top-level claims used by older Alfaeq sessions.
create or replace function private.is_platform_staff()
returns boolean
language sql
stable
set search_path to 'pg_catalog','auth','private'
as $function$
  select
    coalesce(auth.jwt()->>'app_role','') in ('admin','owner','developer')
    or coalesce((auth.jwt()->>'admin')::boolean,false)
    or coalesce((auth.jwt()->>'owner')::boolean,false)
    or coalesce((auth.jwt()->>'developer')::boolean,false)
    or coalesce(auth.jwt()->'app_metadata'->>'app_role','') in ('admin','owner','developer')
    or coalesce((auth.jwt()->'app_metadata'->>'admin')::boolean,false)
    or coalesce((auth.jwt()->'app_metadata'->>'owner')::boolean,false)
    or coalesce((auth.jwt()->'app_metadata'->>'developer')::boolean,false);
$function$;
