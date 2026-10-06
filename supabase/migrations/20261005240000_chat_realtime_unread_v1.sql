-- Realtime chat notifications + unread tracking.
--
-- The app already streams chat_messages/chat_threads/notifications over
-- Realtime. This adds the missing pieces that make chats feel like WeChat:
--   * every chat message notifies the other thread members,
--   * members track the last time they read a thread,
--   * an RPC returns per-thread unread counts for the badge.

-- Last time a member opened the thread. Existing rows default to "now" so the
-- change does not retroactively mark history as unread.
alter table public.chat_members
  add column if not exists last_read_at timestamptz not null default now();

-- Notify every thread member (except the sender) about a new message.
create or replace function private.trg_chat_message_notify()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_member text;
  v_preview text;
  v_title text;
begin
  v_preview := left(coalesce(new.body, ''), 120);
  select coalesce(nullif(t.title, ''), 'محادثة')
    into v_title
  from public.chat_threads t
  where t.id = new.thread_id;

  for v_member in
    select m.user_id from public.chat_members m
    where m.thread_id = new.thread_id and m.user_id is distinct from new.sender_id
  loop
    perform private.notify_user(
      v_member,
      'chat',
      coalesce(v_title, 'رسالة جديدة'),
      v_preview,
      jsonb_build_object('thread_id', new.thread_id, 'sender_id', new.sender_id, 'message_id', new.id)
    );
  end loop;

  return new;
end
$function$;

drop trigger if exists chat_message_notify on public.chat_messages;
create trigger chat_message_notify
  after insert on public.chat_messages
  for each row execute function private.trg_chat_message_notify();

-- Mark a thread read for the signed-in user.
drop function if exists public.mark_thread_read(text);
create or replace function public.mark_thread_read(p_thread_id uuid)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog','public','auth'
as $function$
declare
  v_uid text := auth.uid()::text;
begin
  if v_uid is null then
    raise exception 'authentication_required';
  end if;
  update public.chat_members
  set last_read_at = now()
  where thread_id = p_thread_id and user_id = v_uid;
end
$function$;

revoke all on function public.mark_thread_read(uuid) from public, anon;
grant execute on function public.mark_thread_read(uuid) to authenticated;

-- Per-thread unread counts for the signed-in user (messages since last read,
-- excluding their own). Powers the conversation-list badges.
drop function if exists public.my_thread_unread_counts();
create or replace function public.my_thread_unread_counts()
returns table(thread_id uuid, unread bigint)
language sql
security definer
set search_path to 'pg_catalog','public','auth'
as $function$
  select m.thread_id,
         count(msg.id) filter (where msg.sender_id is distinct from m.user_id) as unread
  from public.chat_members m
  left join public.chat_messages msg
    on msg.thread_id = m.thread_id
   and msg.created_at > m.last_read_at
  where m.user_id = auth.uid()::text
  group by m.thread_id;
$function$;

revoke all on function public.my_thread_unread_counts() from public, anon;
grant execute on function public.my_thread_unread_counts() to authenticated;
