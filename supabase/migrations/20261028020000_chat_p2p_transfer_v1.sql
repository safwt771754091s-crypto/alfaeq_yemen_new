-- WeChat Pay-style peer-to-peer transfer that is posted as a chat bubble.
--
-- This wraps the existing public.wallet_transfer (the only client-initiated
-- wallet mutation, which already moves funds atomically, auto-creates the
-- recipient wallet, and is replay-safe) and additionally writes a structured
-- chat_messages row so the recipient sees a tappable "transfer received"
-- bubble in the conversation. The money logic is not duplicated: the wrapper
-- delegates to wallet_transfer, so ledger/idempotency semantics stay in one
-- place.

-- How many other members a thread has. Only a 1:1 conversation may receive a
-- transfer bubble, because in a group the recipient would be ambiguous.
create or replace function public.thread_member_count(p_thread_id uuid)
returns integer
language sql
security definer
set search_path to ''
as $function$
  select count(*)::integer from public.chat_members m where m.thread_id = p_thread_id;
$function$;
revoke all on function public.thread_member_count(uuid) from public, anon;
grant execute on function public.thread_member_count(uuid) to authenticated;

-- The other participant of a 1:1 thread (with display name), so a client that
-- only knows the thread id can offer the transfer button. Returns null row for
-- group threads or if the caller is not a member.
create or replace function public.direct_thread_peer(p_thread_id uuid)
returns table(peer_uid text, peer_name text)
language sql
security definer
set search_path to ''
as $function$
  select m.user_id as peer_uid,
         coalesce(nullif(trim(u.name), ''), 'مستخدم الفائق') as peer_name
    from public.chat_members m
    join public.chat_threads t on t.id = m.thread_id
    left join public.users u on u.uid = m.user_id
   where m.thread_id = p_thread_id
     and t.thread_type = 'direct'
     and m.user_id <> coalesce(auth.uid()::text, '')
     and private.is_thread_member(p_thread_id)
   limit 1;
$function$;

revoke all on function public.direct_thread_peer(uuid) from public, anon;
grant execute on function public.direct_thread_peer(uuid) to authenticated;

-- Send a transfer to the other member of a 1:1 thread and post a chat bubble.
drop function if exists public.chat_transfer_send(uuid, text, numeric, text, text);
create or replace function public.chat_transfer_send(
  p_thread_id uuid,
  p_to_uid text,
  p_amount numeric,
  p_idempotency_key text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid text := auth.uid()::text;
  v_to text := nullif(trim(p_to_uid), '');
  v_members integer;
  v_type text;
  v_cur text;
  v_balance numeric;
  v_message_id uuid;
  v_body text;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if p_thread_id is null then raise exception 'thread_required'; end if;
  if not private.is_thread_member(p_thread_id) then raise exception 'not_a_member'; end if;
  if v_to is null then raise exception 'recipient_required'; end if;
  if v_to = v_uid then raise exception 'cannot_pay_self'; end if;

  -- A transfer bubble names exactly one recipient, so it is only allowed in a
  -- 1:1 thread. A group thread (even one that currently has two members) is
  -- rejected, so it can never turn into an accidental one-to-one transfer.
  select t.thread_type into v_type from public.chat_threads t where t.id = p_thread_id;
  v_members := public.thread_member_count(p_thread_id);
  if v_type is distinct from 'direct' or v_members <> 2 then
    raise exception 'transfer_requires_direct_thread';
  end if;
  if not exists (select 1 from public.chat_members m where m.thread_id = p_thread_id and m.user_id = v_to) then
    raise exception 'recipient_not_in_thread';
  end if;

  -- Reads the wallet currency so the amount matches the wallet the money is
  -- debited from (the client passes the same currency it displays).
  select upper(w.currency) into v_cur
    from public.wallets w
   where w.uid = v_uid and w.status = 'active'
   order by w.updated_at desc nulls last
   limit 1;
  if v_cur is null then raise exception 'wallet_missing'; end if;

  -- Delegates the actual fund movement (atomic, idempotent, auto-creates the
  -- recipient wallet). Raises insufficient_wallet_balance / recipient_not_found
  -- and returns the sender's new balance.
  v_balance := public.wallet_transfer(v_to, p_amount, v_cur, p_idempotency_key, p_note);

  v_body := 'تحويل مبلغ ' || to_char(round(p_amount, 2), 'FM999999999990.00') || ' ' || v_cur
            || coalesce(' • ' || nullif(btrim(p_note), ''), '');

  insert into public.chat_messages(thread_id, sender_id, body, metadata)
  values (
    p_thread_id,
    v_uid,
    v_body,
    jsonb_build_object(
      'kind', 'transfer',
      'to_uid', v_to,
      'from_uid', v_uid,
      'amount', round(p_amount, 2),
      'currency', v_cur,
      'note', nullif(btrim(p_note), ''),
      'status', 'received'
    )
  )
  returning id into v_message_id;

  return jsonb_build_object(
    'message_id', v_message_id,
    'balance', v_balance,
    'currency', v_cur,
    'amount', round(p_amount, 2),
    'to_uid', v_to
  );
end;
$function$;

revoke all on function public.chat_transfer_send(uuid, text, numeric, text, text) from public, anon;
grant execute on function public.chat_transfer_send(uuid, text, numeric, text, text) to authenticated;
