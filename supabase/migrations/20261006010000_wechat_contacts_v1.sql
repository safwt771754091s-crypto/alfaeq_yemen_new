-- WeChat-style contacts directory.
--
-- WeChat's Contacts tab holds saved contacts, groups, and shortcuts to start a
-- chat or invite someone. The app already had `list_my_contacts()` (peers who
-- share a conversation); this adds a real saved-contacts table plus a direct
-- thread starter so tapping a contact opens a one-to-one chat.

create table if not exists public.user_contacts (
  owner_id text not null references public.users(uid) on delete cascade,
  contact_id text not null references public.users(uid) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (owner_id, contact_id),
  constraint user_contacts_not_self check (owner_id <> contact_id)
);

create index if not exists user_contacts_owner_idx on public.user_contacts(owner_id, created_at desc);

alter table public.user_contacts enable row level security;

drop policy if exists "user_contacts_select_own" on public.user_contacts;
create policy "user_contacts_select_own" on public.user_contacts
  for select using (owner_id = auth.uid()::text);

drop policy if exists "user_contacts_insert_own" on public.user_contacts;
create policy "user_contacts_insert_own" on public.user_contacts
  for insert with check (owner_id = auth.uid()::text);

drop policy if exists "user_contacts_delete_own" on public.user_contacts;
create policy "user_contacts_delete_own" on public.user_contacts
  for delete using (owner_id = auth.uid()::text);

-- RLS policies gate rows, but PostgREST still needs table privileges.
grant select, insert, delete on public.user_contacts to authenticated;

-- Saved contacts with their display name; never exposes email/phone.
create or replace function public.my_saved_contacts()
returns table(uid text, name text)
language sql
security definer
set search_path to ''
as $function$
  select c.contact_id as uid,
         coalesce(nullif(trim(u.name), ''), 'مستخدم الفائق') as name
  from public.user_contacts c
  join public.users u on u.uid = c.contact_id
  where c.owner_id = auth.uid()::text
  order by name;
$function$;

revoke all on function public.my_saved_contacts() from public, anon;
grant execute on function public.my_saved_contacts() to authenticated;

-- Start (or reuse) a one-to-one thread with a peer. Only the two participants
-- are members, so the thread stays private.
drop function if exists public.start_direct_thread(text);
create or replace function public.start_direct_thread(p_peer_uid text)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid text := auth.uid()::text;
  v_thread uuid;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if nullif(trim(p_peer_uid), '') is null or p_peer_uid = v_uid then
    raise exception 'invalid_peer';
  end if;
  if not exists (select 1 from public.users where uid = p_peer_uid) then
    raise exception 'peer_not_found';
  end if;

  select t.id into v_thread
  from public.chat_threads t
  where t.thread_type = 'direct'
    and exists (select 1 from public.chat_members m where m.thread_id = t.id and m.user_id = v_uid)
    and exists (select 1 from public.chat_members m where m.thread_id = t.id and m.user_id = p_peer_uid)
    and (select count(*) from public.chat_members m where m.thread_id = t.id) = 2
  limit 1;

  if v_thread is not null then
    return v_thread;
  end if;

  insert into public.chat_threads(created_by, thread_type, title)
  values (v_uid, 'direct', '')
  returning id into v_thread;

  insert into public.chat_members(thread_id, user_id)
  values (v_thread, v_uid), (v_thread, p_peer_uid)
  on conflict do nothing;

  return v_thread;
end;
$function$;

revoke all on function public.start_direct_thread(text) from public, anon;
grant execute on function public.start_direct_thread(text) to authenticated;

-- Resolve the peer's display name for each direct thread, so the Chats list can
-- show a person's name instead of an empty group-style title.
create or replace function public.my_direct_thread_peers()
returns table(thread_id uuid, peer_name text)
language sql
security definer
set search_path to ''
as $function$
  select t.id as thread_id,
         coalesce(nullif(trim(u.name), ''), 'مستخدم الفائق') as peer_name
  from public.chat_threads t
  join public.chat_members other
    on other.thread_id = t.id and other.user_id <> auth.uid()::text
  join public.users u on u.uid = other.user_id
  where t.thread_type = 'direct'
    and exists (
      select 1 from public.chat_members me
      where me.thread_id = t.id and me.user_id = auth.uid()::text
    );
$function$;

revoke all on function public.my_direct_thread_peers() from public, anon;
grant execute on function public.my_direct_thread_peers() to authenticated;

-- Keep the contacts directory live (saved contacts + shared-thread peers).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'chat_members'
  ) then
    alter publication supabase_realtime add table public.chat_members;
  end if;
end $$;
