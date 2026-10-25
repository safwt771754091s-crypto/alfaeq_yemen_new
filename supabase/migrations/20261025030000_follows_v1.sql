-- Follows (المتابعة): WeChat-style follow graph between users and stores.
-- Additive only: one table, RLS, and a follower-count trigger. No object altered.

-- target_id is text because public.stores.id is text while auth.users.id is uuid;
-- the app passes a user id as its uuid string.
create table if not exists public.follows (
  follower_id uuid not null references auth.users(id) on delete cascade,
  target_type text not null check (target_type in ('store', 'user')),
  target_id text not null,
  created_at timestamptz not null default now(),
  primary key (follower_id, target_type, target_id)
);
create index if not exists follows_target_idx on public.follows (target_type, target_id);
create index if not exists follows_follower_idx on public.follows (follower_id);

alter table public.follows enable row level security;

-- Anyone signed in may read the graph (needed for follower counts / "following"
-- state). A user may only create or remove their OWN follow rows.
drop policy if exists follows_read on public.follows;
create policy follows_read on public.follows for select to authenticated using (true);

drop policy if exists follows_insert on public.follows;
create policy follows_insert on public.follows for insert to authenticated
  with check (follower_id = auth.uid());

drop policy if exists follows_delete on public.follows;
create policy follows_delete on public.follows for delete to authenticated
  using (follower_id = auth.uid());

grant select, insert, delete on public.follows to authenticated;

-- Keep stores.follower_count in sync when the target is a store. The column is
-- added here only if a compatible one does not already exist.
alter table public.stores add column if not exists follower_count integer not null default 0;

create or replace function private.follow_count_sync()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    if new.target_type = 'store' then
      update public.stores set follower_count = follower_count + 1 where id = new.target_id;
    end if;
    return new;
  end if;
  if old.target_type = 'store' then
    update public.stores set follower_count = greatest(follower_count - 1, 0) where id = old.target_id;
  end if;
  return old;
end $$;

drop trigger if exists follows_count on public.follows;
create trigger follows_count after insert or delete on public.follows
  for each row execute function private.follow_count_sync();

-- ---------------------------------------------------------------------------
-- RPCs the app calls.
-- ---------------------------------------------------------------------------

-- Toggle the caller's follow of a target. Returns the new followed state.
create or replace function public.follow_toggle(p_target_type text, p_target_id text)
returns boolean language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_exists boolean;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if p_target_type not in ('store', 'user') then
    raise exception 'invalid_target_type';
  end if;

  select exists (
    select 1 from public.follows
    where follower_id = v_uid and target_type = p_target_type and target_id = p_target_id
  ) into v_exists;

  if v_exists then
    delete from public.follows
    where follower_id = v_uid and target_type = p_target_type and target_id = p_target_id;
    return false;
  end if;

  insert into public.follows (follower_id, target_type, target_id)
  values (v_uid, p_target_type, p_target_id)
  on conflict do nothing;
  return true;
end $$;

-- Follower count + whether the caller follows the target, in one round trip.
create or replace function public.follow_state(p_target_type text, p_target_id text)
returns table (follower_count bigint, following boolean)
language sql stable security definer set search_path = public, pg_temp as $$
  select
    (select count(*) from public.follows f
      where f.target_type = p_target_type and f.target_id = p_target_id) as follower_count,
    exists (select 1 from public.follows f
      where f.target_type = p_target_type and f.target_id = p_target_id
        and f.follower_id = auth.uid()) as following;
$$;

-- The caller's own following list, newest first, with a display label.
create or replace function public.my_follows(p_limit integer default 100)
returns table (target_type text, target_id text, label text, created_at timestamptz)
language sql stable security definer set search_path = public, pg_temp as $$
  select f.target_type, f.target_id,
    case
      when f.target_type = 'store' then coalesce((select s.name from public.stores s where s.id = f.target_id), 'متجر')
      else coalesce(
        (select coalesce(nullif(u.raw_user_meta_data->>'full_name', ''), nullif(u.raw_user_meta_data->>'name', ''), 'مستخدم')
           from auth.users u where u.id::text = f.target_id),
        'مستخدم')
    end as label,
    f.created_at
  from public.follows f
  where f.follower_id = auth.uid()
  order by f.created_at desc
  limit greatest(1, least(coalesce(p_limit, 100), 500));
$$;

revoke all on function public.follow_toggle(text, text) from public, anon;
revoke all on function public.follow_state(text, text) from public, anon;
revoke all on function public.my_follows(integer) from public, anon;
grant execute on function public.follow_toggle(text, text) to authenticated;
grant execute on function public.follow_state(text, text) to authenticated;
grant execute on function public.my_follows(integer) to authenticated;

-- Realtime so follower counts refresh live.
do $$ begin
  alter publication supabase_realtime add table public.follows;
exception when duplicate_object then null; when undefined_object then null; end $$;
