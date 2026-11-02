-- Official Accounts (الحسابات الرسمية) — a WeChat-style 公众号 platform.
--
-- Any signed-in user may open an account (personal or business), publish
-- articles and gain followers; readers subscribe to a feed and read articles
-- in-app. Additive only: new tables, RLS, triggers, a storage bucket and RPCs.
-- No existing object is altered.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table if not exists public.official_accounts (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  bio text not null default '',
  avatar_url text,
  kind text not null default 'personal' check (kind in ('personal', 'business', 'platform')),
  owner_id uuid not null references auth.users(id) on delete cascade,
  verified boolean not null default false,
  follower_count integer not null default 0 check (follower_count >= 0),
  article_count integer not null default 0 check (article_count >= 0),
  status text not null default 'active' check (status in ('active', 'suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists official_accounts_owner_idx on public.official_accounts (owner_id);
create index if not exists official_accounts_created_idx on public.official_accounts (created_at desc);

create table if not exists public.account_articles (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.official_accounts(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (length(btrim(title)) between 1 and 200),
  cover_url text,
  body text not null default '',
  view_count integer not null default 0 check (view_count >= 0),
  like_count integer not null default 0 check (like_count >= 0),
  published boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists account_articles_account_idx on public.account_articles (account_id, created_at desc);
create index if not exists account_articles_created_idx on public.account_articles (created_at desc);

create table if not exists public.account_followers (
  account_id uuid not null references public.official_accounts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (account_id, user_id)
);
create index if not exists account_followers_user_idx on public.account_followers (user_id);

alter table public.official_accounts enable row level security;
alter table public.account_articles enable row level security;
alter table public.account_followers enable row level security;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
drop policy if exists official_accounts_read on public.official_accounts;
create policy official_accounts_read on public.official_accounts for select to authenticated
  using (status = 'active' or owner_id = auth.uid() or private.is_platform_staff());

drop policy if exists official_accounts_insert on public.official_accounts;
create policy official_accounts_insert on public.official_accounts for insert to authenticated
  with check (owner_id = auth.uid());

drop policy if exists official_accounts_update on public.official_accounts;
create policy official_accounts_update on public.official_accounts for update to authenticated
  using (owner_id = auth.uid() or private.is_platform_staff())
  with check (owner_id = auth.uid() or private.is_platform_staff());

drop policy if exists official_accounts_delete on public.official_accounts;
create policy official_accounts_delete on public.official_accounts for delete to authenticated
  using (owner_id = auth.uid() or private.is_platform_staff());

drop policy if exists account_articles_read on public.account_articles;
create policy account_articles_read on public.account_articles for select to authenticated
  using (published or author_id = auth.uid() or private.is_platform_staff());

drop policy if exists account_articles_insert on public.account_articles;
create policy account_articles_insert on public.account_articles for insert to authenticated
  with check (
    author_id = auth.uid()
    and exists (select 1 from public.official_accounts a where a.id = account_id and a.owner_id = auth.uid())
  );

drop policy if exists account_articles_update on public.account_articles;
create policy account_articles_update on public.account_articles for update to authenticated
  using (author_id = auth.uid() or private.is_platform_staff())
  with check (author_id = auth.uid() or private.is_platform_staff());

drop policy if exists account_articles_delete on public.account_articles;
create policy account_articles_delete on public.account_articles for delete to authenticated
  using (author_id = auth.uid() or private.is_platform_staff());

drop policy if exists account_followers_read on public.account_followers;
create policy account_followers_read on public.account_followers for select to authenticated
  using (user_id = auth.uid() or private.is_platform_staff());

drop policy if exists account_followers_insert on public.account_followers;
create policy account_followers_insert on public.account_followers for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists account_followers_delete on public.account_followers;
create policy account_followers_delete on public.account_followers for delete to authenticated
  using (user_id = auth.uid());

revoke all on public.official_accounts from public, anon;
revoke all on public.account_articles from public, anon;
revoke all on public.account_followers from public, anon;
grant select, insert, update, delete on public.official_accounts to authenticated;
grant select, insert, update, delete on public.account_articles to authenticated;
grant select, insert, delete on public.account_followers to authenticated;
grant all on public.official_accounts to service_role;
grant all on public.account_articles to service_role;
grant all on public.account_followers to service_role;

-- ---------------------------------------------------------------------------
-- Triggers: follower/article counters and updated_at (SECURITY DEFINER so the
-- counts cannot be forged by a direct client UPDATE).
-- ---------------------------------------------------------------------------
create or replace function private.account_follower_count_sync()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    update public.official_accounts set follower_count = follower_count + 1 where id = new.account_id;
    return new;
  end if;
  update public.official_accounts set follower_count = greatest(follower_count - 1, 0) where id = old.account_id;
  return old;
end $$;

drop trigger if exists account_followers_count on public.account_followers;
create trigger account_followers_count after insert or delete on public.account_followers
  for each row execute function private.account_follower_count_sync();

create or replace function private.account_article_count_sync()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    if new.published then
      update public.official_accounts set article_count = article_count + 1 where id = new.account_id;
    end if;
    return new;
  end if;
  if tg_op = 'DELETE' then
    if old.published then
      update public.official_accounts set article_count = greatest(article_count - 1, 0) where id = old.account_id;
    end if;
    return old;
  end if;
  if old.published and not new.published then
    update public.official_accounts set article_count = greatest(article_count - 1, 0) where id = new.account_id;
  elsif not old.published and new.published then
    update public.official_accounts set article_count = article_count + 1 where id = new.account_id;
  end if;
  return new;
end $$;

drop trigger if exists account_articles_count on public.account_articles;
create trigger account_articles_count after insert or delete or update of published on public.account_articles
  for each row execute function private.account_article_count_sync();

create or replace function private.account_touch_updated_at()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists official_accounts_touch on public.official_accounts;
create trigger official_accounts_touch before update on public.official_accounts
  for each row execute function private.account_touch_updated_at();

drop trigger if exists account_articles_touch on public.account_articles;
create trigger account_articles_touch before update on public.account_articles
  for each row execute function private.account_touch_updated_at();

-- ---------------------------------------------------------------------------
-- Read RPCs (resolve owner display name/avatar from auth metadata and expose
-- follow state without leaking the users table).
-- ---------------------------------------------------------------------------
create or replace function public.official_accounts_list(p_limit integer default 50, p_offset integer default 0)
returns table (
  id uuid, slug text, name text, bio text, avatar_url text, kind text,
  verified boolean, follower_count integer, article_count integer,
  created_at timestamptz, following boolean, is_owner boolean
)
language sql stable security definer set search_path = public, pg_temp as $$
  select a.id, a.slug, a.name, a.bio, a.avatar_url, a.kind,
         a.verified, a.follower_count, a.article_count, a.created_at,
         exists (select 1 from public.account_followers f where f.account_id = a.id and f.user_id = auth.uid()) as following,
         a.owner_id = auth.uid() as is_owner
  from public.official_accounts a
  where a.status = 'active' or a.owner_id = auth.uid() or private.is_platform_staff()
  order by a.verified desc, a.follower_count desc, a.created_at desc
  limit greatest(1, least(coalesce(p_limit, 50), 100))
  offset greatest(0, coalesce(p_offset, 0));
$$;

create or replace function public.official_account_detail(p_id uuid)
returns table (
  id uuid, slug text, name text, bio text, avatar_url text, kind text,
  verified boolean, follower_count integer, article_count integer,
  created_at timestamptz, following boolean, is_owner boolean
)
language sql stable security definer set search_path = public, pg_temp as $$
  select a.id, a.slug, a.name, a.bio, a.avatar_url, a.kind,
         a.verified, a.follower_count, a.article_count, a.created_at,
         exists (select 1 from public.account_followers f where f.account_id = a.id and f.user_id = auth.uid()) as following,
         a.owner_id = auth.uid() as is_owner
  from public.official_accounts a
  where a.id = p_id
    and (a.status = 'active' or a.owner_id = auth.uid() or private.is_platform_staff());
$$;

create or replace function public.account_articles_list(p_account_id uuid default null, p_limit integer default 30, p_offset integer default 0)
returns table (
  id uuid, account_id uuid, account_name text, account_avatar text, account_verified boolean,
  title text, cover_url text, excerpt text, view_count integer, like_count integer,
  published boolean, created_at timestamptz, is_owner boolean
)
language sql stable security definer set search_path = public, pg_temp as $$
  select ar.id, ar.account_id,
         a.name as account_name, a.avatar_url as account_avatar, a.verified as account_verified,
         ar.title, ar.cover_url, left(btrim(ar.body), 160) as excerpt,
         ar.view_count, ar.like_count, ar.published, ar.created_at,
         a.owner_id = auth.uid() as is_owner
  from public.account_articles ar
  join public.official_accounts a on a.id = ar.account_id
  where (p_account_id is null or ar.account_id = p_account_id)
    and (ar.published or a.owner_id = auth.uid() or private.is_platform_staff())
    and (a.status = 'active' or a.owner_id = auth.uid() or private.is_platform_staff())
  order by ar.created_at desc
  limit greatest(1, least(coalesce(p_limit, 30), 100))
  offset greatest(0, coalesce(p_offset, 0));
$$;

-- Full article body for the reader (visibility enforced like the list).
create or replace function public.account_article_detail(p_id uuid)
returns table (
  id uuid, account_id uuid, account_name text, account_avatar text, account_verified boolean,
  title text, cover_url text, body text, view_count integer, like_count integer,
  published boolean, created_at timestamptz, is_owner boolean
)
language sql stable security definer set search_path = public, pg_temp as $$
  select ar.id, ar.account_id, a.name, a.avatar_url, a.verified,
         ar.title, ar.cover_url, ar.body, ar.view_count, ar.like_count,
         ar.published, ar.created_at, a.owner_id = auth.uid()
  from public.account_articles ar
  join public.official_accounts a on a.id = ar.account_id
  where ar.id = p_id
    and (ar.published or a.owner_id = auth.uid() or private.is_platform_staff())
    and (a.status = 'active' or a.owner_id = auth.uid() or private.is_platform_staff());
$$;

-- Articles from the accounts the caller follows — the subscriber feed.
create or replace function public.my_account_feed(p_limit integer default 30, p_offset integer default 0)
returns table (
  id uuid, account_id uuid, account_name text, account_avatar text, account_verified boolean,
  title text, cover_url text, excerpt text, view_count integer, like_count integer,
  created_at timestamptz
)
language sql stable security definer set search_path = public, pg_temp as $$
  select ar.id, ar.account_id, a.name, a.avatar_url, a.verified,
         ar.title, ar.cover_url, left(btrim(ar.body), 160),
         ar.view_count, ar.like_count, ar.created_at
  from public.account_articles ar
  join public.official_accounts a on a.id = ar.account_id
  where ar.published
    and a.status = 'active'
    and exists (select 1 from public.account_followers f where f.account_id = a.id and f.user_id = auth.uid())
  order by ar.created_at desc
  limit greatest(1, least(coalesce(p_limit, 30), 100))
  offset greatest(0, coalesce(p_offset, 0));
$$;

create or replace function public.account_following_list()
returns table (
  id uuid, slug text, name text, bio text, avatar_url text, kind text,
  verified boolean, follower_count integer, article_count integer, following boolean
)
language sql stable security definer set search_path = public, pg_temp as $$
  select a.id, a.slug, a.name, a.bio, a.avatar_url, a.kind,
         a.verified, a.follower_count, a.article_count, true as following
  from public.official_accounts a
  join public.account_followers f on f.account_id = a.id
  where f.user_id = auth.uid() and a.status = 'active'
  order by a.name asc
  limit 200;
$$;

-- Toggle follow; returns the new state. The counters are maintained by trigger.
create or replace function public.account_toggle_follow(p_account_id uuid)
returns boolean language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_exists boolean;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if not exists (select 1 from public.official_accounts a where a.id = p_account_id and a.status = 'active') then
    raise exception 'account not found';
  end if;
  select exists (select 1 from public.account_followers f where f.account_id = p_account_id and f.user_id = v_uid) into v_exists;
  if v_exists then
    delete from public.account_followers f where f.account_id = p_account_id and f.user_id = v_uid;
    return false;
  end if;
  insert into public.account_followers (account_id, user_id) values (p_account_id, v_uid);
  return true;
end $$;

-- Bounded view counter for an article.
create or replace function public.account_article_register_view(p_article_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.account_articles ar
     set view_count = least(ar.view_count + 1, 2147483647)
   where ar.id = p_article_id
     and (ar.published or ar.author_id = auth.uid() or private.is_platform_staff());
end $$;

revoke all on function public.official_accounts_list(integer, integer) from public, anon;
revoke all on function public.official_account_detail(uuid) from public, anon;
revoke all on function public.account_articles_list(uuid, integer, integer) from public, anon;
revoke all on function public.account_article_detail(uuid) from public, anon;
revoke all on function public.my_account_feed(integer, integer) from public, anon;
revoke all on function public.account_following_list() from public, anon;
revoke all on function public.account_toggle_follow(uuid) from public, anon;
revoke all on function public.account_article_register_view(uuid) from public, anon;
grant execute on function public.official_accounts_list(integer, integer) to authenticated, service_role;
grant execute on function public.official_account_detail(uuid) to authenticated, service_role;
grant execute on function public.account_articles_list(uuid, integer, integer) to authenticated, service_role;
grant execute on function public.account_article_detail(uuid) to authenticated, service_role;
grant execute on function public.my_account_feed(integer, integer) to authenticated, service_role;
grant execute on function public.account_following_list() to authenticated, service_role;
grant execute on function public.account_toggle_follow(uuid) to authenticated, service_role;
grant execute on function public.account_article_register_view(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Storage bucket for account avatars and article covers (public read,
-- owner-scoped writes keyed by the first path segment = auth.uid()).
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('official-accounts', 'official-accounts', true, 5242880,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists official_accounts_media_read on storage.objects;
create policy official_accounts_media_read on storage.objects for select
  using (bucket_id = 'official-accounts');

drop policy if exists official_accounts_media_write on storage.objects;
create policy official_accounts_media_write on storage.objects for insert to authenticated
  with check (bucket_id = 'official-accounts' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists official_accounts_media_update on storage.objects;
create policy official_accounts_media_update on storage.objects for update to authenticated
  using (bucket_id = 'official-accounts' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists official_accounts_media_delete on storage.objects;
create policy official_accounts_media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'official-accounts' and (storage.foldername(name))[1] = auth.uid()::text);
