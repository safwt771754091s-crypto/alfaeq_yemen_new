-- WeChat-style group conversations.
-- RLS only lets a thread creator insert THEMSELVES as a member, so creating a
-- group (creator + other members) and listing a user's chat peers require
-- SECURITY DEFINER functions that run with the server's privileges.

create or replace function public.create_group_thread(p_title text, p_member_uids text[] default '{}')
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

  insert into public.chat_threads(created_by, thread_type, title)
  values (v_uid, 'group', coalesce(nullif(trim(p_title), ''), 'مجموعة'))
  returning id into v_thread;

  insert into public.chat_members(thread_id, user_id)
  values (v_thread, v_uid)
  on conflict do nothing;

  if p_member_uids is not null and array_length(p_member_uids, 1) > 0 then
    insert into public.chat_members(thread_id, user_id)
    select v_thread, u.uid
    from unnest(p_member_uids) as u(uid)
    join public.users usr on usr.uid = u.uid
    where u.uid <> v_uid
    on conflict do nothing;
  end if;

  return v_thread;
end;
$function$;

create or replace function public.add_group_members(p_thread_id uuid, p_member_uids text[])
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid text := auth.uid()::text;
  v_added integer;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if not exists (select 1 from public.chat_members where thread_id = p_thread_id and user_id = v_uid) then
    raise exception 'not authorized';
  end if;

  with ins as (
    insert into public.chat_members(thread_id, user_id)
    select p_thread_id, u.uid
    from unnest(coalesce(p_member_uids, '{}'::text[])) as u(uid)
    join public.users usr on usr.uid = u.uid
    on conflict do nothing
    returning 1
  )
  select count(*) into v_added from ins;

  return coalesce(v_added, 0);
end;
$function$;

-- Peers who share at least one conversation with the caller (for the contacts
-- directory). Returns only uid + display name, never emails or other fields.
create or replace function public.list_my_contacts()
returns table(uid text, name text)
language sql
security definer
set search_path to ''
as $function$
  select distinct u.uid, coalesce(nullif(trim(u.name), ''), 'مستخدم الفائق') as name
  from public.chat_members mine
  join public.chat_members peer on peer.thread_id = mine.thread_id and peer.user_id <> mine.user_id
  join public.users u on u.uid = peer.user_id
  where mine.user_id = auth.uid()::text
  order by name;
$function$;

revoke all on function public.create_group_thread(text, text[]) from public, anon;
revoke all on function public.add_group_members(uuid, text[]) from public, anon;
revoke all on function public.list_my_contacts() from public, anon;

grant execute on function public.create_group_thread(text, text[]) to authenticated;
grant execute on function public.add_group_members(uuid, text[]) to authenticated;
grant execute on function public.list_my_contacts() to authenticated;
