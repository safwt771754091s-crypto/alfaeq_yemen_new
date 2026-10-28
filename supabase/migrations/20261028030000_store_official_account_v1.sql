-- WeChat-style "official account" chat with a store.
--
-- A customer opens a 1:1 conversation with a store; the store immediately
-- replies with a tappable service menu, and each menu item is answered
-- automatically with live data (products, the customer's orders, store info).
-- The merchant (store owner) is added as a member so they can join in.
--
-- chat_threads has no store column, so the store<->customer<->thread relation
-- lives in its own table with a unique (store_id, customer_uid) so a customer
-- always reuses one conversation per store.

create table if not exists public.store_chat_threads (
  thread_id uuid primary key references public.chat_threads(id) on delete cascade,
  store_id text not null,
  customer_uid text not null,
  created_at timestamptz not null default now(),
  unique (store_id, customer_uid)
);

-- Store auto-replies are authored by the platform (like WeChat official
-- accounts), not by a signed-in user, so they carry no sender. chat_messages
-- historically required a real sender; relax that to allow system messages.
alter table public.chat_messages alter column sender_id drop not null;

alter table public.store_chat_threads enable row level security;

drop policy if exists store_chat_threads_read on public.store_chat_threads;
create policy store_chat_threads_read on public.store_chat_threads
for select to authenticated
using (customer_uid = (select auth.uid())::text or private.is_platform_staff());

create index if not exists store_chat_threads_customer_idx on public.store_chat_threads(customer_uid);

-- The store's display name and contact details, for the menu auto-replies.
create or replace function public.store_chat_store(p_thread_id uuid)
returns table(store_id text, store_name text, phone text, address text, owner_uid text)
language sql
security definer
set search_path to ''
as $function$
  select s.id, s.name, s.phone, s.address, s.owner_id
    from public.store_chat_threads t
    join public.stores s on s.id = t.store_id
   where t.thread_id = p_thread_id
     and (t.customer_uid = coalesce(auth.uid()::text, '') or private.is_platform_staff());
$function$;

revoke all on function public.store_chat_store(uuid) from public, anon;
grant execute on function public.store_chat_store(uuid) to authenticated;

-- Opens (or reuses) the customer's conversation with a store and, on first
-- open, posts the welcome service menu.
drop function if exists public.start_store_thread(text);
create or replace function public.start_store_thread(p_store_id text)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid text := auth.uid()::text;
  v_store public.stores%rowtype;
  v_thread uuid;
  v_menu jsonb;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if nullif(btrim(p_store_id), '') is null then raise exception 'store_required'; end if;

  select * into v_store from public.stores s where s.id = p_store_id and s.status = 'approved';
  if v_store.id is null then raise exception 'store_not_found'; end if;

  select t.thread_id into v_thread
    from public.store_chat_threads t
   where t.store_id = p_store_id and t.customer_uid = v_uid;
  if v_thread is not null then
    return v_thread;
  end if;

  insert into public.chat_threads(created_by, thread_type, title)
  values (v_uid, 'store', v_store.name)
  returning id into v_thread;

  insert into public.chat_members(thread_id, user_id)
  values (v_thread, v_uid)
  on conflict do nothing;

  if v_store.owner_id is not null and v_store.owner_id <> v_uid then
    insert into public.chat_members(thread_id, user_id)
    values (v_thread, v_store.owner_id)
    on conflict do nothing;
  end if;

  insert into public.store_chat_threads(thread_id, store_id, customer_uid)
  values (v_thread, p_store_id, v_uid);

  v_menu := jsonb_build_object(
    'kind', 'store_menu',
    'store_id', p_store_id,
    'store_name', v_store.name,
    'options', jsonb_build_array(
      jsonb_build_object('action', 'products', 'label', '🛍️ المنتجات'),
      jsonb_build_object('action', 'orders', 'label', '📦 طلباتي'),
      jsonb_build_object('action', 'info', 'label', '📍 معلومات المتجر')
    )
  );

  insert into public.chat_messages(thread_id, sender_id, body, metadata)
  values (
    v_thread,
    null,
    'مرحباً بك في ' || v_store.name || ' 👋 كيف نخدمك؟',
    v_menu
  );

  return v_thread;
end;
$function$;

revoke all on function public.start_store_thread(text) from public, anon;
grant execute on function public.start_store_thread(text) to authenticated;

-- Handles a tapped menu item: records the customer's choice and posts the
-- store's automatic reply with live data.
drop function if exists public.store_chat_action(uuid, text);
create or replace function public.store_chat_action(p_thread_id uuid, p_action text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid text := auth.uid()::text;
  v_store public.stores%rowtype;
  v_customer text;
  v_action text := lower(coalesce(nullif(btrim(p_action), ''), ''));
  v_label text;
  v_reply text;
  v_kind text := 'store_reply';
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if not private.is_thread_member(p_thread_id) then raise exception 'not_a_member'; end if;
  if v_action not in ('products', 'orders', 'info') then raise exception 'unknown_action'; end if;

  select s.* into v_store
    from public.store_chat_threads t
    join public.stores s on s.id = t.store_id
   where t.thread_id = p_thread_id;
  if v_store.id is null then raise exception 'not_a_store_thread'; end if;
  select t.customer_uid into v_customer from public.store_chat_threads t where t.thread_id = p_thread_id;

  if v_action = 'products' then
    v_label := '🛍️ المنتجات';
    select coalesce(string_agg(line, E'\n'), 'لا توجد منتجات معروضة حالياً.')
      into v_reply
      from (
        select p.name || ' — ' || to_char(p.price, 'FM999999990.00') || ' ' || p.currency as line
          from public.products p
         where p.store_id = v_store.id and p.status = 'active'
         order by p.created_at desc nulls last
         limit 6
      ) sub;
  elsif v_action = 'orders' then
    v_label := '📦 طلباتي';
    select coalesce(string_agg(line, E'\n'), 'لا توجد طلبات سابقة في هذا المتجر.')
      into v_reply
      from (
        select 'طلب ' || left(o.id, 10) || ' — ' || coalesce(o.status, '') ||
               coalesce(' • ' || to_char(o.total, 'FM999999990.00') || ' ' || coalesce(o.currency, ''), '') as line
          from public.orders o
         where o.customer_id = v_customer
           and v_store.id = any(coalesce(o.merchant_ids, array[]::text[]))
         order by o.created_at desc nulls last
         limit 4
      ) sub;
  else
    v_label := '📍 معلومات المتجر';
    v_reply := 'الاسم: ' || v_store.name
      || coalesce(E'\nالعنوان: ' || nullif(v_store.address, ''), '')
      || coalesce(E'\nالهاتف: ' || nullif(v_store.phone, ''), '');
  end if;

  insert into public.chat_messages(thread_id, sender_id, body, metadata)
  values (p_thread_id, v_uid, v_label, jsonb_build_object('kind', 'store_choice', 'action', v_action));

  insert into public.chat_messages(thread_id, sender_id, body, metadata)
  values (p_thread_id, null, v_reply, jsonb_build_object('kind', v_kind, 'action', v_action, 'store_id', v_store.id));

  if v_store.owner_id is not null and v_store.owner_id <> v_uid then
    perform private.notify_user(
      v_store.owner_id,
      'store',
      v_store.name,
      'رسالة جديدة من عميل في ' || v_store.name,
      jsonb_build_object('thread_id', p_thread_id, 'action', v_action)
    );
  end if;

  return jsonb_build_object('action', v_action, 'reply', v_reply, 'store_id', v_store.id);
end;
$function$;

revoke all on function public.store_chat_action(uuid, text) from public, anon;
grant execute on function public.store_chat_action(uuid, text) to authenticated;
