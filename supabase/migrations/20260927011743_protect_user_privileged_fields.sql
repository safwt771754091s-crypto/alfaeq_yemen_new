-- Prevent ordinary authenticated users from self-escalating privileged role fields.
create or replace function private.protect_user_privileges()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  is_staff boolean;
begin
  is_staff := coalesce((auth.jwt()->>'app_role') in ('admin','owner','developer'), false)
    or coalesce((auth.jwt()->>'admin')::boolean, false)
    or coalesce((auth.jwt()->>'owner')::boolean, false)
    or coalesce((auth.jwt()->>'developer')::boolean, false)
    or coalesce((auth.jwt()->'app_metadata'->>'app_role') in ('admin','owner','developer'), false)
    or coalesce((auth.jwt()->'app_metadata'->>'admin')::boolean, false)
    or coalesce((auth.jwt()->'app_metadata'->>'owner')::boolean, false)
    or coalesce((auth.jwt()->'app_metadata'->>'developer')::boolean, false);

  if not is_staff then
    new.role := old.role;
    new.admin := old.admin;
    new.owner := old.owner;
    new.developer := old.developer;
    new.access_level := old.access_level;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

revoke all on function private.protect_user_privileges() from public;

drop trigger if exists protect_user_privileges on public.users;
create trigger protect_user_privileges
before update on public.users
for each row
execute function private.protect_user_privileges();
