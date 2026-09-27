-- Keep public.users synchronized with Supabase Auth users.
-- Roles are intentionally provisioned separately; new users are never granted staff privileges here.

create or replace function private.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_provider text;
begin
  v_name := coalesce(
    nullif(trim(new.raw_user_meta_data->>'full_name'), ''),
    nullif(trim(new.raw_user_meta_data->>'name'), ''),
    ''
  );
  v_provider := coalesce(new.raw_app_meta_data->>'provider', 'email');

  insert into public.users (
    uid, email, name, role, metadata, updated_at
  )
  values (
    new.id::text,
    new.email,
    v_name,
    'customer',
    jsonb_build_object('provider', v_provider),
    now()
  )
  on conflict (uid) do update
    set email = excluded.email,
        name = case
          when nullif(excluded.name, '') is not null then excluded.name
          else public.users.name
        end,
        updated_at = now();

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_profile on auth.users;

create trigger on_auth_user_created_profile
after insert on auth.users
for each row
execute function private.handle_new_user_profile();
