drop policy if exists automation_staff_select on public.automation_jobs;
create policy automation_staff_select on public.automation_jobs
for select to authenticated
using (exists (select 1 from public.users u where u.uid=(select auth.uid())::text
  and (coalesce(u.admin,false) or coalesce(u.developer,false) or coalesce(u.owner,false))));

drop policy if exists chat_member_members on public.chat_members;
create policy chat_member_members on public.chat_members
for select to authenticated
using (user_id=(select auth.uid())::text);

drop policy if exists chat_member_messages on public.chat_messages;
create policy chat_member_messages on public.chat_messages
for all to authenticated
using (exists (select 1 from public.chat_members m where m.thread_id=chat_messages.thread_id and m.user_id=(select auth.uid())::text))
with check (sender_id=(select auth.uid())::text);

drop policy if exists chat_member_select on public.chat_threads;
create policy chat_member_select on public.chat_threads
for select to authenticated
using (exists (select 1 from public.chat_members m where m.thread_id=chat_threads.id and m.user_id=(select auth.uid())::text));

drop policy if exists notifications_owner_all on public.notifications;
create policy notifications_owner_all on public.notifications
for all to authenticated
using (user_id=(select auth.uid())::text)
with check (user_id=(select auth.uid())::text);

drop policy if exists wallet_ledger_owner_select on public.wallet_ledger;
create policy wallet_ledger_owner_select on public.wallet_ledger
for select to authenticated
using (user_id=(select auth.uid())::text);

drop index if exists public.idx_orders_customer_created;
drop index if exists public.idx_wallet_transactions_uid_created;
