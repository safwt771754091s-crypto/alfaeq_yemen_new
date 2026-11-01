-- WeChat-style message reactions ("متفاعل") for chats.
--
-- Any thread member can react to a message with an emoji; reactions are shown
-- under the bubble with live counts and can be toggled by tapping. Additive
-- only: one new table, a SECURITY DEFINER membership helper, RLS policies and
-- a Realtime publication entry. Nothing existing is dropped or rewritten.

-- ---------------------------------------------------------------------------
-- Table. thread_id is denormalised (filled by trigger) so the client can stream
-- reactions for a single thread instead of every reaction in the project.
-- ---------------------------------------------------------------------------
create table if not exists public.message_reactions (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.chat_messages(id) on delete cascade,
  thread_id uuid not null references public.chat_threads(id) on delete cascade,
  user_id text not null,
  emoji text not null,
  created_at timestamptz not null default now(),
  constraint message_reactions_emoji_len check (char_length(emoji) between 1 and 16),
  unique (message_id, user_id, emoji)
);

create index if not exists message_reactions_thread_idx
  on public.message_reactions (thread_id);

-- ---------------------------------------------------------------------------
-- Membership helper. SECURITY DEFINER so the RLS policies can check the
-- message's thread without recursing into chat_messages' own RLS.
-- ---------------------------------------------------------------------------
create or replace function private.is_message_member(p_message_id uuid)
returns boolean
language sql
security definer
set search_path to ''
stable
as $function$
  select exists (
    select 1
    from public.chat_messages m
    join public.chat_members cm on cm.thread_id = m.thread_id
    where m.id = p_message_id
      and cm.user_id = auth.uid()::text
  );
$function$;

revoke all on function private.is_message_member(uuid) from public, anon;
grant execute on function private.is_message_member(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Populate thread_id from the parent message; the client never supplies it.
-- ---------------------------------------------------------------------------
create or replace function private.trg_reaction_set_thread()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  select m.thread_id into new.thread_id
  from public.chat_messages m
  where m.id = new.message_id;
  if new.thread_id is null then
    raise exception 'message_not_found';
  end if;
  return new;
end
$function$;

drop trigger if exists reaction_set_thread on public.message_reactions;
create trigger reaction_set_thread
  before insert on public.message_reactions
  for each row execute function private.trg_reaction_set_thread();

-- ---------------------------------------------------------------------------
-- RLS: members of the message's thread can read and add reactions; you can
-- only remove your own. Platform staff can read (moderation parity).
-- ---------------------------------------------------------------------------
alter table public.message_reactions enable row level security;

drop policy if exists message_reactions_select on public.message_reactions;
create policy message_reactions_select on public.message_reactions
  for select using (private.is_message_member(message_id) or private.is_platform_staff());

drop policy if exists message_reactions_insert on public.message_reactions;
create policy message_reactions_insert on public.message_reactions
  for insert with check (user_id = auth.uid()::text and private.is_message_member(message_id));

drop policy if exists message_reactions_delete on public.message_reactions;
create policy message_reactions_delete on public.message_reactions
  for delete using (user_id = auth.uid()::text);

revoke all on table public.message_reactions from anon;
grant select, insert, delete on table public.message_reactions to authenticated;

-- ---------------------------------------------------------------------------
-- Realtime: reactions appear live for everyone in the thread.
-- ---------------------------------------------------------------------------
do $do$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      alter publication supabase_realtime add table public.message_reactions;
    exception when duplicate_object then
      null;
    end;
  end if;
end
$do$;
