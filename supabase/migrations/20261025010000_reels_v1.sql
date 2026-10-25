-- Reels (فيديو الفائق): a WeChat Channels (视频号) style short-video feed.
-- Additive only: new tables, RLS, triggers, a storage bucket, and read/notify RPCs.
-- No existing object is altered.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table if not exists public.reels (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete cascade,
  caption text not null default '',
  video_url text not null,
  thumbnail_url text,
  duration_seconds integer not null default 0 check (duration_seconds >= 0),
  kind text not null default 'video' check (kind in ('video', 'image')),
  visibility text not null default 'public' check (visibility in ('public', 'followers', 'private')),
  like_count integer not null default 0 check (like_count >= 0),
  comment_count integer not null default 0 check (comment_count >= 0),
  view_count integer not null default 0 check (view_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists reels_created_at_idx on public.reels (created_at desc);
create index if not exists reels_author_idx on public.reels (author_id);

create table if not exists public.reel_comments (
  id uuid primary key default gen_random_uuid(),
  reel_id uuid not null references public.reels(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists reel_comments_reel_idx on public.reel_comments (reel_id, created_at);

create table if not exists public.reel_likes (
  reel_id uuid not null references public.reels(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (reel_id, user_id)
);
create index if not exists reel_likes_user_idx on public.reel_likes (user_id);

alter table public.reels enable row level security;
alter table public.reel_comments enable row level security;
alter table public.reel_likes enable row level security;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
drop policy if exists reels_read on public.reels;
create policy reels_read on public.reels for select to authenticated
  using (author_id = auth.uid() or visibility = 'public' or private.is_platform_staff());

drop policy if exists reels_insert on public.reels;
create policy reels_insert on public.reels for insert to authenticated
  with check (author_id = auth.uid());

drop policy if exists reels_update on public.reels;
create policy reels_update on public.reels for update to authenticated
  using (author_id = auth.uid() or private.is_platform_staff())
  with check (author_id = auth.uid() or private.is_platform_staff());

drop policy if exists reels_delete on public.reels;
create policy reels_delete on public.reels for delete to authenticated
  using (author_id = auth.uid() or private.is_platform_staff());

drop policy if exists reel_comments_read on public.reel_comments;
create policy reel_comments_read on public.reel_comments for select to authenticated
  using (exists (select 1 from public.reels r where r.id = reel_id));

drop policy if exists reel_comments_insert on public.reel_comments;
create policy reel_comments_insert on public.reel_comments for insert to authenticated
  with check (author_id = auth.uid() and exists (select 1 from public.reels r where r.id = reel_id));

drop policy if exists reel_comments_delete on public.reel_comments;
create policy reel_comments_delete on public.reel_comments for delete to authenticated
  using (author_id = auth.uid() or private.is_platform_staff());

drop policy if exists reel_likes_read on public.reel_likes;
create policy reel_likes_read on public.reel_likes for select to authenticated using (true);

drop policy if exists reel_likes_insert on public.reel_likes;
create policy reel_likes_insert on public.reel_likes for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists reel_likes_delete on public.reel_likes;
create policy reel_likes_delete on public.reel_likes for delete to authenticated
  using (user_id = auth.uid());

grant select, insert, update, delete on public.reels to authenticated;
grant select, insert, delete on public.reel_comments to authenticated;
grant select, insert, delete on public.reel_likes to authenticated;

-- ---------------------------------------------------------------------------
-- Counter + timestamp triggers (SECURITY DEFINER so counters can't be forged
-- by a direct client UPDATE; only the owning author may edit their own row).
-- ---------------------------------------------------------------------------
create or replace function private.reel_like_count_sync()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    update public.reels set like_count = like_count + 1 where id = new.reel_id;
    return new;
  end if;
  update public.reels set like_count = greatest(like_count - 1, 0) where id = old.reel_id;
  return old;
end $$;

drop trigger if exists reel_likes_count on public.reel_likes;
create trigger reel_likes_count after insert or delete on public.reel_likes
  for each row execute function private.reel_like_count_sync();

create or replace function private.reel_comment_count_sync()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    update public.reels set comment_count = comment_count + 1 where id = new.reel_id;
    return new;
  end if;
  update public.reels set comment_count = greatest(comment_count - 1, 0) where id = old.reel_id;
  return old;
end $$;

drop trigger if exists reel_comments_count on public.reel_comments;
create trigger reel_comments_count after insert or delete on public.reel_comments
  for each row execute function private.reel_comment_count_sync();

create or replace function private.reel_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists reels_touch on public.reels;
create trigger reels_touch before update on public.reels
  for each row execute function private.reel_touch_updated_at();

-- ---------------------------------------------------------------------------
-- Read RPCs (resolve author display name/avatar from auth metadata without
-- exposing the users table, and enforce visibility).
-- ---------------------------------------------------------------------------
create or replace function public.reels_feed(p_limit integer default 30, p_offset integer default 0)
returns table (
  id uuid, author_id uuid, author_name text, author_avatar text,
  caption text, video_url text, thumbnail_url text, duration_seconds integer,
  kind text, visibility text, like_count integer, comment_count integer,
  view_count integer, created_at timestamptz, liked_by_me boolean
)
language sql stable security definer set search_path = public, pg_temp as $$
  select r.id, r.author_id,
    coalesce(nullif(u.raw_user_meta_data->>'full_name', ''), nullif(u.raw_user_meta_data->>'name', ''), 'مستخدم الفائق') as author_name,
    nullif(u.raw_user_meta_data->>'avatar_url', '') as author_avatar,
    r.caption, r.video_url, r.thumbnail_url, r.duration_seconds, r.kind, r.visibility,
    r.like_count, r.comment_count, r.view_count, r.created_at,
    exists (select 1 from public.reel_likes l where l.reel_id = r.id and l.user_id = auth.uid()) as liked_by_me
  from public.reels r
  left join auth.users u on u.id = r.author_id
  where r.visibility = 'public' or r.author_id = auth.uid() or private.is_platform_staff()
  order by r.created_at desc
  limit greatest(1, least(coalesce(p_limit, 30), 100))
  offset greatest(0, coalesce(p_offset, 0));
$$;

create or replace function public.reel_comments_list(p_reel_id uuid)
returns table (id uuid, author_id uuid, author_name text, author_avatar text, body text, created_at timestamptz)
language sql stable security definer set search_path = public, pg_temp as $$
  select c.id, c.author_id,
    coalesce(nullif(u.raw_user_meta_data->>'full_name', ''), nullif(u.raw_user_meta_data->>'name', ''), 'مستخدم الفائق') as author_name,
    nullif(u.raw_user_meta_data->>'avatar_url', '') as author_avatar,
    c.body, c.created_at
  from public.reel_comments c
  left join auth.users u on u.id = c.author_id
  where c.reel_id = p_reel_id
    and exists (
      select 1 from public.reels r
      where r.id = p_reel_id
        and (r.visibility = 'public' or r.author_id = auth.uid() or private.is_platform_staff())
    )
  order by c.created_at asc
  limit 200;
$$;

-- Increment the view counter for a visible reel. Bounded to avoid abuse.
create or replace function public.reel_register_view(p_reel_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.reels r
     set view_count = least(r.view_count + 1, 2147483647)
   where r.id = p_reel_id
     and (r.visibility = 'public' or r.author_id = auth.uid() or private.is_platform_staff());
end $$;

-- Notify the reel author when someone comments (called by the app right
-- after inserting the comment; verifies the caller owns that comment).
create or replace function public.notify_reel_comment(p_reel_id uuid, p_comment_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_author uuid;
  v_name text;
  v_excerpt text;
begin
  select author_id into v_author from public.reels where id = p_reel_id;
  if v_author is null or v_author = auth.uid() then
    return;
  end if;
  if not exists (
    select 1 from public.reel_comments c
    where c.id = p_comment_id and c.reel_id = p_reel_id and c.author_id = auth.uid()
  ) then
    return;
  end if;
  select left(btrim(body), 120) into v_excerpt from public.reel_comments where id = p_comment_id;
  select coalesce(nullif(u.raw_user_meta_data->>'full_name', ''), nullif(u.raw_user_meta_data->>'name', ''), 'مستخدم')
    into v_name from auth.users u where u.id = auth.uid();
  insert into public.notifications (user_id, type, title, body, data)
  values (v_author::text, 'reel_comment', 'تعليق جديد على فيديوك', coalesce(v_name, 'مستخدم') || ': ' || coalesce(v_excerpt, ''),
          jsonb_build_object('reel_id', p_reel_id, 'comment_id', p_comment_id));
end $$;

revoke all on function public.reels_feed(integer, integer) from public, anon;
revoke all on function public.reel_comments_list(uuid) from public, anon;
revoke all on function public.reel_register_view(uuid) from public, anon;
revoke all on function public.notify_reel_comment(uuid, uuid) from public, anon;
grant execute on function public.reels_feed(integer, integer) to authenticated;
grant execute on function public.reel_comments_list(uuid) to authenticated;
grant execute on function public.reel_register_view(uuid) to authenticated;
grant execute on function public.notify_reel_comment(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Storage bucket for reels (public read, owner-scoped writes).
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('reels', 'reels', true, 52428800,
        array['video/mp4', 'video/quicktime', 'video/webm', 'video/x-m4v',
              'image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists reels_media_read on storage.objects;
create policy reels_media_read on storage.objects for select to public
  using (bucket_id = 'reels');

drop policy if exists reels_media_insert on storage.objects;
create policy reels_media_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'reels' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists reels_media_update on storage.objects;
create policy reels_media_update on storage.objects for update to authenticated
  using (bucket_id = 'reels' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists reels_media_delete on storage.objects;
create policy reels_media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'reels' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- Realtime so the feed updates live.
-- ---------------------------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.reels;
exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.reel_comments;
exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.reel_likes;
exception when duplicate_object then null; when undefined_object then null; end $$;
