-- Restore the designated platform owner's full role and platform account.
-- The account is identified by its verified owner email, not by a client-side claim.
drop trigger if exists protect_user_privileges on public.users;

update public.users
set role = 'owner',
    owner = true,
    admin = true,
    developer = true,
    access_level = 100,
    metadata = coalesce(metadata, '{}'::jsonb)
      || jsonb_build_object(
        'platform_role','owner',
        'privileges','full'
      ),
    updated_at = now()
where email = 'safwt771754091s@gmail.com';

create trigger protect_user_privileges
before update on public.users
for each row
execute function private.protect_user_privileges();

update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data,'{}'::jsonb)
  || jsonb_build_object(
    'app_role','owner',
    'role','owner',
    'owner',true,
    'admin',true,
    'developer',true
  )
where email = 'safwt771754091s@gmail.com';

insert into public.platform_accounts
  (id, account_type, owner_uid, display_name, status, default_currency, metadata, updated_at)
select
  gen_random_uuid(),
  'platform',
  u.uid,
  'Alfaeq Yemen',
  'active',
  'YER',
  jsonb_build_object('managed_by','owner'),
  now()
from public.users u
where u.email = 'safwt771754091s@gmail.com'
  and not exists (
    select 1
    from public.platform_accounts a
    where a.owner_uid = u.uid
  );
