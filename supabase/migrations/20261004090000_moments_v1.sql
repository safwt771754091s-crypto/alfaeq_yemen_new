-- Moments (朋友圈): a WeChat-style social feed for the Alfaeq Yemen super app.
-- Additive only: new tables, RLS, triggers, a storage bucket, and read/notify RPCs.
-- No existing object is altered.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table if not exists public.moments (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete cascade,
  content text not null default '',
  media_urls text[] not null default '{}',
  visibility text not null default 'public' check (visibility in ('public', 'followers', 'private')),
  like_count integer not null default 0 check (like_count >= 0),
  comment_count integer not null default 0 check (comment_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint moments_body_or_media check (length(btrim(content)) > 0 or array_length(media_urls, 1) is not null)
);
create index if not exists moments_created_at_idx on public.moments (created_at desc);
create index if not exists moments_author_idx on public.moments (author_id);

create table if not exists public.moment_comments (
  id uuid primary key default gen_random_uuid(),
  moment_id uuid not null references public.moments(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists moment_comments_moment_idx on public.moment_comments (moment_id, created_at);

create table if not exists public.moment_likes (
  moment_id uuid not null references public.moments(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (moment_id, user_id)
);
create index if not exists moment_likes_user_idx on public.moment_likes (user_id);

alter table public.moments enable row level security;
alter table public.moment_comments enable row level security;
alter table public.moment_likes enable row level security;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
drop policy if exists moments_read on public.moments;
create policy moments_read on public.moments for select to authenticated
  using (author_id = auth.uid() or visibility = 'public' or private.is_platform_staff());

drop policy if exists moments_insert on public.moments;
create policy moments_insert on public.moments for insert to authenticated
  with check (author_id = auth.uid());

drop policy if exists moments_update on public.moments;
create policy moments_update on public.moments for update to authenticated
  using (author_id = auth.uid() or private.is_platform_staff())
  with check (author_id = auth.uid() or private.is_platform_staff());

drop policy if exists moments_delete on public.moments;
create policy moments_delete on public.moments for delete to authenticated
  using (author_id = auth.uid() or private.is_platform_staff());

drop policy if exists moment_comments_read on public.moment_comments;
create policy moment_comments_read on public.moment_comments for select to authenticated
  using (exists (select 1 from public.moments m where m.id = moment_id));

drop policy if exists moment_comments_insert on public.moment_comments;
create policy moment_comments_insert on public.moment_comments for insert to authenticated
  with check (author_id = auth.uid() and exists (select 1 from public.moments m where m.id = moment_id));

drop policy if exists moment_comments_delete on public.moment_comments;
create policy moment_comments_delete on public.moment_comments for delete to authenticated
  using (author_id = auth.uid() or private.is_platform_staff());

drop policy if exists moment_likes_read on public.moment_likes;
create policy moment_likes_read on public.moment_likes for select to authenticated using (true);

drop policy if exists moment_likes_insert on public.moment_likes;
create policy moment_likes_insert on public.moment_likes for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists moment_likes_delete on public.moment_likes;
create policy moment_likes_delete on public.moment_likes for delete to authenticated
  using (user_id = auth.uid());

grant select, insert, update, delete on public.moments to authenticated;
grant select, insert, delete on public.moment_comments to authenticated;
grant select, insert, delete on public.moment_likes to authenticated;

-- ---------------------------------------------------------------------------
-- Counter + timestamp triggers (SECURITY DEFINER so counters can't be forged
-- by a direct client UPDATE; only the owning author may edit their own row).
-- ---------------------------------------------------------------------------
create or replace function private.moment_like_count_sync()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    update public.moments set like_count = like_count + 1 where id = new.moment_id;
    return new;
  end if;
  update public.moments set like_count = greatest(like_count - 1, 0) where id = old.moment_id;
  return old;
end $$;

drop trigger if exists moment_likes_count on public.moment_likes;
create trigger moment_likes_count after insert or delete on public.moment_likes
  for each row execute function private.moment_like_count_sync();

create or replace function private.moment_comment_count_sync()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    update public.moments set comment_count = comment_count + 1 where id = new.moment_id;
    return new;
  end if;
  update public.moments set comment_count = greatest(comment_count - 1, 0) where id = old.moment_id;
  return old;
end $$;

drop trigger if exists moment_comments_count on public.moment_comments;
create trigger moment_comments_count after insert or delete on public.moment_comments
  for each row execute function private.moment_comment_count_sync();

create or replace function private.moment_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists moments_touch on public.moments;
create trigger moments_touch before update on public.moments
  for each row execute function private.moment_touch_updated_at();

-- ---------------------------------------------------------------------------
-- Read RPCs (resolve author display name/avatar from auth metadata without
-- exposing the users table, and enforce visibility).
-- ---------------------------------------------------------------------------
create or replace function public.moments_feed(p_limit integer default 40)
returns table (
  id uuid, author_id uuid, author_name text, author_avatar text,
  content text, media_urls text[], visibility text,
  like_count integer, comment_count integer, created_at timestamptz, liked_by_me boolean
)
language sql stable security definer set search_path = public, pg_temp as $$
  select m.id, m.author_id,
    coalesce(nullif(u.raw_user_meta_data->>'full_name', ''), nullif(u.raw_user_meta_data->>'name', ''), 'مستخدم الفائق') as author_name,
    nullif(u.raw_user_meta_data->>'avatar_url', '') as author_avatar,
    m.content, m.media_urls, m.visibility, m.like_count, m.comment_count, m.created_at,
    exists (select 1 from public.moment_likes l where l.moment_id = m.id and l.user_id = auth.uid()) as liked_by_me
  from public.moments m
  left join auth.users u on u.id = m.author_id
  where m.visibility = 'public' or m.author_id = auth.uid() or private.is_platform_staff()
  order by m.created_at desc
  limit greatest(1, least(coalesce(p_limit, 40), 100));
$$;

create or replace function public.moment_comments_list(p_moment_id uuid)
returns table (id uuid, author_id uuid, author_name text, author_avatar text, body text, created_at timestamptz)
language sql stable security definer set search_path = public, pg_temp as $$
  select c.id, c.author_id,
    coalesce(nullif(u.raw_user_meta_data->>'full_name', ''), nullif(u.raw_user_meta_data->>'name', ''), 'مستخدم الفائق') as author_name,
    nullif(u.raw_user_meta_data->>'avatar_url', '') as author_avatar,
    c.body, c.created_at
  from public.moment_comments c
  left join auth.users u on u.id = c.author_id
  where c.moment_id = p_moment_id
    and exists (
      select 1 from public.moments m
      where m.id = p_moment_id
        and (m.visibility = 'public' or m.author_id = auth.uid() or private.is_platform_staff())
    )
  order by c.created_at asc
  limit 200;
$$;

-- Notify the moment author when someone comments (called by the app right
-- after inserting the comment; verifies the caller owns that comment).
create or replace function public.notify_moment_comment(p_moment_id uuid, p_comment_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_author uuid;
  v_name text;
  v_excerpt text;
begin
  select author_id into v_author from public.moments where id = p_moment_id;
  if v_author is null or v_author = auth.uid() then
    return;
  end if;
  if not exists (
    select 1 from public.moment_comments c
    where c.id = p_comment_id and c.moment_id = p_moment_id and c.author_id = auth.uid()
  ) then
    return;
  end if;
  select left(btrim(body), 120) into v_excerpt from public.moment_comments where id = p_comment_id;
  select coalesce(nullif(u.raw_user_meta_data->>'full_name', ''), nullif(u.raw_user_meta_data->>'name', ''), 'مستخدم')
    into v_name from auth.users u where u.id = auth.uid();
  insert into public.notifications (user_id, type, title, body, data)
  values (v_author::text, 'moment_comment', 'تعليق جديد على منشورك', coalesce(v_name, 'مستخدم') || ': ' || coalesce(v_excerpt, ''),
          jsonb_build_object('moment_id', p_moment_id, 'comment_id', p_comment_id));
end $$;

revoke all on function public.moments_feed(integer) from public, anon;
revoke all on function public.moment_comments_list(uuid) from public, anon;
revoke all on function public.notify_moment_comment(uuid, uuid) from public, anon;
grant execute on function public.moments_feed(integer) to authenticated;
grant execute on function public.moment_comments_list(uuid) to authenticated;
grant execute on function public.notify_moment_comment(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Storage bucket for moment photos (public read, owner-scoped writes).
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('moments', 'moments', true, 10485760, array['image/jpeg', 'image/png', 'image/webp', 'image/gif'])
on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists moments_media_read on storage.objects;
create policy moments_media_read on storage.objects for select to public
  using (bucket_id = 'moments');

drop policy if exists moments_media_insert on storage.objects;
create policy moments_media_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'moments' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists moments_media_update on storage.objects;
create policy moments_media_update on storage.objects for update to authenticated
  using (bucket_id = 'moments' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists moments_media_delete on storage.objects;
create policy moments_media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'moments' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- Realtime so the feed updates live.
-- ---------------------------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.moments;
exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.moment_comments;
exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.moment_likes;
exception when duplicate_object then null; when undefined_object then null; end $$;
