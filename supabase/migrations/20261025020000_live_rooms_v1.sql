-- Live rooms (غرف البث): a WeChat-style live streaming lobby and watch room.
-- Additive only: new tables, RLS, triggers, read RPCs. No existing object is altered.
--
-- Video transport is delegated to a player URL (HLS/WebRTC egress provided by
-- the merchant's streaming tool). This migration models the platform layer:
-- who is live, who may watch, chat, gift and moderate.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table if not exists public.live_rooms (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references auth.users(id) on delete cascade,
  title text not null default '',
  cover_url text,
  playback_url text,
  status text not null default 'scheduled' check (status in ('scheduled', 'live', 'ended')),
  store_id uuid,
  viewer_count integer not null default 0 check (viewer_count >= 0),
  like_count integer not null default 0 check (like_count >= 0),
  gift_total integer not null default 0 check (gift_total >= 0),
  started_at timestamptz,
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists live_rooms_status_idx on public.live_rooms (status, created_at desc);
create index if not exists live_rooms_host_idx on public.live_rooms (host_id);

create table if not exists public.live_messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.live_rooms(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (length(btrim(body)) between 1 and 500),
  kind text not null default 'chat' check (kind in ('chat', 'join', 'gift', 'system')),
  created_at timestamptz not null default now()
);
create index if not exists live_messages_room_idx on public.live_messages (room_id, created_at);

create table if not exists public.live_likes (
  room_id uuid not null references public.live_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

alter table public.live_rooms enable row level security;
alter table public.live_messages enable row level security;
alter table public.live_likes enable row level security;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
drop policy if exists live_rooms_read on public.live_rooms;
create policy live_rooms_read on public.live_rooms for select to authenticated
  using (status <> 'scheduled' or host_id = auth.uid() or private.is_platform_staff());

drop policy if exists live_rooms_insert on public.live_rooms;
create policy live_rooms_insert on public.live_rooms for insert to authenticated
  with check (host_id = auth.uid());

drop policy if exists live_rooms_update on public.live_rooms;
create policy live_rooms_update on public.live_rooms for update to authenticated
  using (host_id = auth.uid() or private.is_platform_staff())
  with check (host_id = auth.uid() or private.is_platform_staff());

drop policy if exists live_rooms_delete on public.live_rooms;
create policy live_rooms_delete on public.live_rooms for delete to authenticated
  using (host_id = auth.uid() or private.is_platform_staff());

drop policy if exists live_messages_read on public.live_messages;
create policy live_messages_read on public.live_messages for select to authenticated
  using (exists (
    select 1 from public.live_rooms r
    where r.id = room_id and (r.status <> 'scheduled' or r.host_id = auth.uid() or private.is_platform_staff())
  ));

drop policy if exists live_messages_insert on public.live_messages;
create policy live_messages_insert on public.live_messages for insert to authenticated
  with check (author_id = auth.uid() and exists (
    select 1 from public.live_rooms r
    where r.id = room_id and (r.status <> 'scheduled' or r.host_id = auth.uid() or private.is_platform_staff())
  ));

drop policy if exists live_messages_delete on public.live_messages;
create policy live_messages_delete on public.live_messages for delete to authenticated
  using (author_id = auth.uid() or private.is_platform_staff());

drop policy if exists live_likes_read on public.live_likes;
create policy live_likes_read on public.live_likes for select to authenticated using (true);

drop policy if exists live_likes_insert on public.live_likes;
create policy live_likes_insert on public.live_likes for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists live_likes_delete on public.live_likes;
create policy live_likes_delete on public.live_likes for delete to authenticated
  using (user_id = auth.uid());

grant select, insert, update, delete on public.live_rooms to authenticated;
grant select, insert, delete on public.live_messages to authenticated;
grant select, insert, delete on public.live_likes to authenticated;

-- ---------------------------------------------------------------------------
-- Counter + timestamp triggers
-- ---------------------------------------------------------------------------
create or replace function private.live_like_count_sync()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    update public.live_rooms set like_count = like_count + 1 where id = new.room_id;
    return new;
  end if;
  update public.live_rooms set like_count = greatest(like_count - 1, 0) where id = old.room_id;
  return old;
end $$;

drop trigger if exists live_likes_count on public.live_likes;
create trigger live_likes_count after insert or delete on public.live_likes
  for each row execute function private.live_like_count_sync();

-- Gifts are recorded as live_messages of kind 'gift'; the trigger keeps the
-- room's gift_total honest so a client can never forge the scoreboard.
create or replace function private.live_gift_total_sync()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' and new.kind = 'gift' then
    update public.live_rooms set gift_total = gift_total + 1 where id = new.room_id;
    return new;
  end if;
  if tg_op = 'DELETE' and old.kind = 'gift' then
    update public.live_rooms set gift_total = greatest(gift_total - 1, 0) where id = old.room_id;
    return old;
  end if;
  return coalesce(new, old);
end $$;

drop trigger if exists live_gift_total on public.live_messages;
create trigger live_gift_total after insert or delete on public.live_messages
  for each row execute function private.live_gift_total_sync();

create or replace function private.live_room_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists live_rooms_touch on public.live_rooms;
create trigger live_rooms_touch before update on public.live_rooms
  for each row execute function private.live_room_touch_updated_at();

-- ---------------------------------------------------------------------------
-- Lifecycle RPCs (host only)
-- ---------------------------------------------------------------------------
create or replace function public.live_start_room(p_title text, p_playback_url text default null)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;
  insert into public.live_rooms (host_id, title, playback_url, status, started_at)
  values (auth.uid(), coalesce(nullif(btrim(p_title), ''), 'بث مباشر'), nullif(btrim(p_playback_url), ''), 'live', now())
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.live_end_room(p_room_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.live_rooms
     set status = 'ended', ended_at = now()
   where id = p_room_id and host_id = auth.uid();
  if not found then
    raise exception 'not_room_host' using errcode = '42501';
  end if;
end $$;

-- Bounded viewer counter; best-effort telemetry called on join/leave.
create or replace function public.live_register_view(p_room_id uuid, p_delta integer default 1)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.live_rooms r
     set viewer_count = greatest(0, least(r.viewer_count + greatest(-1, least(coalesce(p_delta, 1), 1)), 2147483647))
   where r.id = p_room_id
     and (r.status <> 'scheduled' or r.host_id = auth.uid() or private.is_platform_staff());
end $$;

-- ---------------------------------------------------------------------------
-- Read RPCs (resolve host name/avatar without exposing the users table)
-- ---------------------------------------------------------------------------
create or replace function public.live_rooms_feed(p_status text default 'live', p_limit integer default 30)
returns table (
  id uuid, host_id uuid, host_name text, host_avatar text,
  title text, cover_url text, playback_url text, status text, store_id uuid,
  viewer_count integer, like_count integer, gift_total integer,
  started_at timestamptz, created_at timestamptz
)
language sql stable security definer set search_path = public, pg_temp as $$
  select r.id, r.host_id,
    coalesce(nullif(u.raw_user_meta_data->>'full_name', ''), nullif(u.raw_user_meta_data->>'name', ''), 'مستخدم الفائق') as host_name,
    nullif(u.raw_user_meta_data->>'avatar_url', '') as host_avatar,
    r.title, r.cover_url, r.playback_url, r.status, r.store_id,
    r.viewer_count, r.like_count, r.gift_total, r.started_at, r.created_at
  from public.live_rooms r
  left join auth.users u on u.id = r.host_id
  where (r.status <> 'scheduled' or r.host_id = auth.uid() or private.is_platform_staff())
    and (coalesce(p_status, 'live') = 'all' or r.status = p_status)
  order by (r.status = 'live') desc, r.created_at desc
  limit greatest(1, least(coalesce(p_limit, 30), 100));
$$;

create or replace function public.live_messages_list(p_room_id uuid, p_limit integer default 100)
returns table (id uuid, author_id uuid, author_name text, author_avatar text, body text, kind text, created_at timestamptz)
language sql stable security definer set search_path = public, pg_temp as $$
  select m.id, m.author_id,
    coalesce(nullif(u.raw_user_meta_data->>'full_name', ''), nullif(u.raw_user_meta_data->>'name', ''), 'مستخدم الفائق') as author_name,
    nullif(u.raw_user_meta_data->>'avatar_url', '') as author_avatar,
    m.body, m.kind, m.created_at
  from public.live_messages m
  left join auth.users u on u.id = m.author_id
  where m.room_id = p_room_id
    and exists (
      select 1 from public.live_rooms r
      where r.id = p_room_id
        and (r.status <> 'scheduled' or r.host_id = auth.uid() or private.is_platform_staff())
    )
  order by m.created_at asc
  limit greatest(1, least(coalesce(p_limit, 100), 300));
$$;

revoke all on function public.live_start_room(text, text) from public, anon;
revoke all on function public.live_end_room(uuid) from public, anon;
revoke all on function public.live_register_view(uuid, integer) from public, anon;
revoke all on function public.live_rooms_feed(text, integer) from public, anon;
revoke all on function public.live_messages_list(uuid, integer) from public, anon;
grant execute on function public.live_start_room(text, text) to authenticated;
grant execute on function public.live_end_room(uuid) to authenticated;
grant execute on function public.live_register_view(uuid, integer) to authenticated;
grant execute on function public.live_rooms_feed(text, integer) to authenticated;
grant execute on function public.live_messages_list(uuid, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Realtime so the lobby and chat update live.
-- ---------------------------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.live_rooms;
exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.live_messages;
exception when duplicate_object then null; when undefined_object then null; end $$;
