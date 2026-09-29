-- Harden support-chat RPCs by using caller privileges and explicit RLS.
-- The RPCs remain the application contract; authorization moves to table policies.

create policy "chat_thread_creator_insert"
on public.chat_threads
for insert
to authenticated
with check ((created_by = (select auth.uid())::text));

create policy "chat_member_self_insert"
on public.chat_members
for insert
to authenticated
with check (
  user_id = (select auth.uid())::text
  and exists (
    select 1
    from public.chat_threads t
    where t.id = chat_members.thread_id
      and t.created_by = (select auth.uid())::text
  )
);

create policy "chat_staff_messages"
on public.chat_messages
for all
to authenticated
using ((select private.is_platform_staff()))
with check (
  (select private.is_platform_staff())
  and sender_id = (select auth.uid())::text
);

alter function public.create_support_thread(text) security invoker;
alter function public.send_chat_message(uuid, text) security invoker;
