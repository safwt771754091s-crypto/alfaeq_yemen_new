-- WeChat-style "join a group by QR code". A group can be shared as a QR that
-- encodes `alfaeq://group?code=<join_code>`. Anyone signed in who scans it
-- becomes a member. Additive only: two nullable/defaulted columns, one partial
-- unique index and three SECURITY DEFINER RPCs. No existing object is dropped.

-- ---------------------------------------------------------------------------
-- Columns: a short, shareable join code per group. New groups get one lazily
-- the first time a member opens the group QR (see group_join_code below).
-- ---------------------------------------------------------------------------
alter table public.chat_threads
  add column if not exists join_code text,
  add column if not exists join_code_created_at timestamptz not null default now();

-- A code is unique across groups, but direct threads and un-coded groups are
-- left out of the index (partial index on non-null codes only).
create unique index if not exists chat_threads_join_code_key
  on public.chat_threads (join_code)
  where join_code is not null;

-- ---------------------------------------------------------------------------
-- group_join_code: members can read the code; pass p_rotate = true to replace
-- it (useful if the link leaked). Generates lazily when missing.
-- ---------------------------------------------------------------------------
create or replace function public.group_join_code(p_thread_id uuid, p_rotate boolean default false)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid text := auth.uid()::text;
  v_type text;
  v_code text;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  select thread_type, join_code into v_type, v_code
  from public.chat_threads
  where id = p_thread_id;

  if v_type is null then raise exception 'not_found'; end if;
  if v_type <> 'group' then raise exception 'not_a_group'; end if;
  if not exists (select 1 from public.chat_members m where m.thread_id = p_thread_id and m.user_id = v_uid) then
    raise exception 'not_a_member';
  end if;

  if p_rotate or v_code is null then
    loop
      -- gen_random_uuid() is core (pg_catalog), so it resolves even with an
      -- empty search_path. 12 hex chars = 48 bits, plenty for a share code.
      v_code := substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
      begin
        update public.chat_threads
           set join_code = v_code, join_code_created_at = now()
         where id = p_thread_id;
        exit;
      exception when unique_violation then
        -- Collision is astronomically unlikely; just retry.
      end;
    end loop;
  end if;

  return v_code;
end;
$function$;

-- ---------------------------------------------------------------------------
-- join_group_by_code: the scanned/pasted code resolves to a group and the
-- caller is added as a member. Idempotent (on conflict do nothing). A wrong or
-- revoked code returns a single generic error so codes cannot be probed.
-- ---------------------------------------------------------------------------
create or replace function public.join_group_by_code(p_code text)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid text := auth.uid()::text;
  v_thread uuid;
  v_code text := lower(btrim(coalesce(p_code, '')));
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if v_code = '' then raise exception 'invalid_code'; end if;

  select id into v_thread
  from public.chat_threads
  where join_code = v_code and thread_type = 'group';

  if v_thread is null then raise exception 'invalid_code'; end if;

  insert into public.chat_members(thread_id, user_id)
  values (v_thread, v_uid)
  on conflict do nothing;

  return v_thread;
end;
$function$;

revoke all on function public.group_join_code(uuid, boolean) from public, anon;
revoke all on function public.join_group_by_code(text) from public, anon;

grant execute on function public.group_join_code(uuid, boolean) to authenticated;
grant execute on function public.join_group_by_code(text) to authenticated;
