-- Fix infinite recursion between the chat_members INSERT policy and the
-- chat_threads SELECT policy.
--
-- `chat_member_self_insert` (chat_members INSERT) referenced chat_threads, whose
-- `chat_member_select` policy referenced chat_members. PostgreSQL detects the
-- cycle and rejects every write with 42P17 "infinite recursion detected in
-- policy for relation chat_members", which broke support-thread creation
-- (create_support_thread) and any membership write.
--
-- Membership visibility now goes through a SECURITY DEFINER helper owned by the
-- table owner (bypasses RLS), which breaks the cycle while still restricting
-- threads to their creator, their members, and platform staff.

create or replace function private.is_thread_member(p_thread_id uuid)
returns boolean
language sql
security definer
stable
set search_path to ''
as $function$
  select exists (
    select 1 from public.chat_members
    where thread_id = p_thread_id
      and user_id = auth.uid()::text
  );
$function$;

revoke all on function private.is_thread_member(uuid) from public, anon;
grant execute on function private.is_thread_member(uuid) to authenticated;

-- Direct client inserts into chat_members are no longer used: membership is
-- written by SECURITY DEFINER RPCs (create_group_thread/add_group_members).
drop policy if exists chat_member_self_insert on public.chat_members;

drop policy if exists chat_member_select on public.chat_threads;
create policy chat_member_select on public.chat_threads
for select
to authenticated
using (
  created_by = (select auth.uid())::text
  or private.is_thread_member(id)
  or (select private.is_platform_staff())
);

-- Support threads are created with the same SECURITY DEFINER pattern as groups.
alter function public.create_support_thread(text) security definer;
