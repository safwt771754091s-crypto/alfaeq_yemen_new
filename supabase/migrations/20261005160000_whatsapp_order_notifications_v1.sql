-- WhatsApp order notifications + invoice delivery (Alfaeq Yemen).
--
-- Adds a durable outbox (public.whatsapp_notifications) plus a staff-only
-- dispatcher that calls the Meta WhatsApp Cloud API through pg_net. Secrets
-- live in Supabase Vault (WHATSAPP_ACCESS_TOKEN, WHATSAPP_PHONE_NUMBER_ID,
-- WHATSAPP_VERIFY_TOKEN) and never reach the Flutter client.
--
-- Additive only: no existing table or function is dropped or narrowed.

-- ---------------------------------------------------------------------------
-- Outbox
-- ---------------------------------------------------------------------------
create table if not exists public.whatsapp_notifications (
  id text primary key default ('wa-' || replace(gen_random_uuid()::text, '-', '')),
  order_id text,
  recipient_role text not null default 'merchant',
  to_phone text,
  body text not null,
  status text not null default 'pending',
  attempts integer not null default 0,
  available_at timestamptz not null default now(),
  request_id bigint,
  error text,
  metadata jsonb not null default '{}'::jsonb,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint whatsapp_notifications_status_check
    check (status in ('pending', 'sent', 'failed'))
);

create index if not exists whatsapp_notifications_due_idx
  on public.whatsapp_notifications(status, available_at);
create index if not exists whatsapp_notifications_order_idx
  on public.whatsapp_notifications(order_id, recipient_role);

alter table public.whatsapp_notifications enable row level security;

drop policy if exists whatsapp_notifications_staff_select on public.whatsapp_notifications;
create policy whatsapp_notifications_staff_select on public.whatsapp_notifications
  for select to authenticated
  using ((select private.is_platform_staff()));

-- ---------------------------------------------------------------------------
-- Vault-backed configuration
-- ---------------------------------------------------------------------------
create or replace function private.whatsapp_secret(p_name text)
returns text
language sql
security definer
set search_path = pg_catalog, vault
as $$
  select decrypted_secret
  from vault.decrypted_secrets
  where name = p_name
  limit 1
$$;

revoke all on function private.whatsapp_secret(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Invoice text builder (single source of truth for WhatsApp + UI)
-- ---------------------------------------------------------------------------
create or replace function public.get_order_invoice(p_order_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_uid text;
  v_order public.orders%rowtype;
  v_lines text := '';
  v_count integer := 0;
  v_total numeric;
  v_currency text;
  v_store_names text;
  v_short text;
begin
  v_uid := auth.uid()::text;

  select * into v_order from public.orders where id = p_order_id;
  if not found then
    raise exception 'order_not_found';
  end if;

  if not (
    private.is_platform_staff()
    or v_order.customer_id = v_uid
    or v_uid = any (coalesce(v_order.merchant_ids, '{}'))
    or exists (select 1 from public.stores s where s.id = any (coalesce(v_order.merchant_ids, '{}')) and s.owner_id = v_uid)
  ) then
    raise exception 'not_authorized';
  end if;

  select coalesce(string_agg(s.name, '، '), '')
    into v_store_names
    from public.stores s
   where s.id = any (coalesce(v_order.merchant_ids, '{}'));

  v_total := coalesce(v_order.display_total, v_order.total, 0);
  v_currency := coalesce(nullif(v_order.display_currency, ''), nullif(v_order.currency, ''), 'USD');

  select coalesce(string_agg(
           '• ' || coalesce(oi.name, 'صنف') || ' × ' || trim(to_char(oi.quantity, 'FM999999990.###'))
           || ' = ' || trim(to_char(coalesce(oi.display_unit_price, oi.unit_price, 0) * oi.quantity, 'FM999999990.##'))
           || ' ' || coalesce(nullif(oi.display_currency, ''), nullif(oi.currency, ''), v_currency),
           E'\n'), ''),
         count(*)
    into v_lines, v_count
    from public.order_items oi
   where oi.order_id = p_order_id;

  if v_count = 0 and jsonb_typeof(v_order.items) = 'array' then
    select coalesce(string_agg(
             '• ' || coalesce(item->>'name', 'صنف') || ' × ' || coalesce(item->>'quantity', '1')
             || ' = ' || coalesce(item->>'line_total', item->>'unit_price', '0')
             || ' ' || coalesce(item->>'currency', v_currency),
             E'\n'), ''),
           count(*)
      into v_lines, v_count
      from jsonb_array_elements(v_order.items) as item;
  end if;

  v_short := case when length(v_order.id) > 8 then left(v_order.id, 8) else v_order.id end;

  return jsonb_build_object(
    'order_id', v_order.id,
    'short_id', v_short,
    'status', v_order.status,
    'delivery_status', v_order.delivery_status,
    'store_names', v_store_names,
    'address', v_order.address,
    'payment_method', v_order.payment_method,
    'total', v_total,
    'currency', v_currency,
    'item_count', v_count,
    'items_text', v_lines,
    'body', '🧾 فاتورة الفائق يمن' || E'\n'
         || 'طلب رقم: ' || v_short || E'\n'
         || 'التاجر: ' || coalesce(nullif(v_store_names, ''), '—') || E'\n'
         || '--------------------------------' || E'\n'
         || coalesce(v_lines, '• لا توجد أصناف') || E'\n'
         || '--------------------------------' || E'\n'
         || 'الإجمالي: ' || trim(to_char(v_total, 'FM999999990.##')) || ' ' || v_currency || E'\n'
         || 'العنوان: ' || coalesce(nullif(v_order.address, ''), '—') || E'\n'
         || 'الدفع: ' || coalesce(nullif(v_order.payment_method, ''), '—')
  );
end;
$$;

revoke all on function public.get_order_invoice(text) from public, anon;
grant execute on function public.get_order_invoice(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Outbound send via WhatsApp Cloud API
-- ---------------------------------------------------------------------------
create or replace function private.whatsapp_send_row(p_row jsonb)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, net, private
as $$
declare
  v_token text;
  v_phone_id text;
  v_to text;
  v_request bigint;
  v_id text := p_row->>'id';
begin
  v_to := regexp_replace(coalesce(p_row->>'to_phone', ''), '[^0-9]', '', 'g');
  if v_to = '' then
    update public.whatsapp_notifications
       set status = 'failed', error = 'missing_phone', updated_at = now()
     where id = v_id;
    return;
  end if;

  v_token := private.whatsapp_secret('WHATSAPP_ACCESS_TOKEN');
  v_phone_id := private.whatsapp_secret('WHATSAPP_PHONE_NUMBER_ID');
  if v_token is null or v_phone_id is null then
    update public.whatsapp_notifications
       set status = 'failed', error = 'whatsapp_not_configured', updated_at = now()
     where id = v_id;
    return;
  end if;

  select net.http_post(
    url := 'https://graph.facebook.com/v21.0/' || v_phone_id || '/messages',
    body := jsonb_build_object(
      'messaging_product', 'whatsapp',
      'recipient_type', 'individual',
      'to', v_to,
      'type', 'text',
      'text', jsonb_build_object('preview_url', false, 'body', coalesce(p_row->>'body', ''))
    ),
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_token,
      'Content-Type', 'application/json'
    )
  ) into v_request;

  update public.whatsapp_notifications
     set status = 'sent', request_id = v_request, sent_at = now(), error = null, updated_at = now()
   where id = v_id;
exception when others then
  update public.whatsapp_notifications
     set status = 'failed', error = left(sqlerrm, 500), updated_at = now()
   where id = v_id;
end;
$$;

revoke all on function private.whatsapp_send_row(jsonb) from public, anon, authenticated;

-- Staff/service dispatcher: drains due outbox rows (with backoff).
create or replace function public.whatsapp_dispatch(p_limit integer default 10)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  r record;
  n integer := 0;
begin
  if not (private.is_platform_staff() or auth.role() = 'service_role') then
    raise exception 'not_authorized';
  end if;

  for r in
    select to_jsonb(w) as row
      from public.whatsapp_notifications w
     where w.status in ('pending', 'failed')
       and w.attempts < 5
       and w.available_at <= now()
     order by w.created_at
     limit greatest(1, least(coalesce(p_limit, 10), 50))
  loop
    update public.whatsapp_notifications
       set attempts = attempts + 1,
           available_at = now() + (least(3600, power(2, attempts + 1) * 15)::text || ' seconds')::interval,
           updated_at = now()
     where id = r.row->>'id';
    perform private.whatsapp_send_row(r.row);
    n := n + 1;
  end loop;

  return n;
end;
$$;

revoke all on function public.whatsapp_dispatch(integer) from public, anon;
grant execute on function public.whatsapp_dispatch(integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Order notification fan-out: merchant(s) + driver (+ customer)
-- ---------------------------------------------------------------------------
create or replace function public.whatsapp_notify_order(
  p_order_id text,
  p_include_customer boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_uid text;
  v_order public.orders%rowtype;
  v_invoice jsonb;
  v_body text;
  v_inserted integer := 0;
  v_merchant_phones text[];
  v_driver_phone text;
  v_customer_phone text;
begin
  v_uid := auth.uid()::text;

  select * into v_order from public.orders where id = p_order_id;
  if not found then
    raise exception 'order_not_found';
  end if;

  if not (
    private.is_platform_staff()
    or v_order.customer_id = v_uid
    or v_uid = any (coalesce(v_order.merchant_ids, '{}'))
    or exists (select 1 from public.stores s where s.id = any (coalesce(v_order.merchant_ids, '{}')) and s.owner_id = v_uid)
  ) then
    raise exception 'not_authorized';
  end if;

  v_invoice := public.get_order_invoice(p_order_id);
  v_body := v_invoice->>'body';

  select array_remove(array_agg(distinct nullif(s.phone, '')), null)
    into v_merchant_phones
    from public.stores s
   where s.id = any (coalesce(v_order.merchant_ids, '{}'));

  v_driver_phone := null;
  if v_order.driver_id is not null then
    select nullif(d.metadata->>'phone', '')
      into v_driver_phone
      from public.drivers d
     where d.uid = v_order.driver_id;
  end if;

  v_customer_phone := null;
  if p_include_customer then
    select nullif(pa.metadata->>'phone', '')
      into v_customer_phone
      from public.platform_accounts pa
     where pa.owner_uid = v_order.customer_id
     order by pa.created_at
     limit 1;
  end if;

  if v_merchant_phones is not null then
    insert into public.whatsapp_notifications(order_id, recipient_role, to_phone, body, metadata)
    select p_order_id, 'merchant', phone, v_body, jsonb_build_object('invoice', true)
      from unnest(v_merchant_phones) as phone;
    v_inserted := v_inserted + coalesce(array_length(v_merchant_phones, 1), 0);
  end if;

  if v_driver_phone is not null then
    insert into public.whatsapp_notifications(order_id, recipient_role, to_phone, body, metadata)
    values (p_order_id, 'driver', v_driver_phone, v_body, jsonb_build_object('invoice', true));
    v_inserted := v_inserted + 1;
  end if;

  if v_customer_phone is not null then
    insert into public.whatsapp_notifications(order_id, recipient_role, to_phone, body, metadata)
    values (p_order_id, 'customer', v_customer_phone, v_body, jsonb_build_object('invoice', true));
    v_inserted := v_inserted + 1;
  end if;

  return jsonb_build_object(
    'ok', true,
    'order_id', p_order_id,
    'queued', v_inserted,
    'merchants', coalesce(array_length(v_merchant_phones, 1), 0),
    'driver', (v_driver_phone is not null),
    'customer', (v_customer_phone is not null),
    'configured', (private.whatsapp_secret('WHATSAPP_ACCESS_TOKEN') is not null
                   and private.whatsapp_secret('WHATSAPP_PHONE_NUMBER_ID') is not null)
  );
end;
$$;

revoke all on function public.whatsapp_notify_order(text, boolean) from public, anon;
grant execute on function public.whatsapp_notify_order(text, boolean) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Queue a custom message (e.g. AI-parsed product confirmation)
-- ---------------------------------------------------------------------------
create or replace function public.whatsapp_enqueue_message(
  p_to_phone text,
  p_body text,
  p_role text default 'customer',
  p_order_id text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_id text;
begin
  if not (private.is_platform_staff() or auth.role() = 'service_role') then
    raise exception 'not_authorized';
  end if;
  insert into public.whatsapp_notifications(order_id, recipient_role, to_phone, body, metadata)
  values (p_order_id, coalesce(nullif(p_role, ''), 'customer'), p_to_phone, p_body, coalesce(p_metadata, '{}'::jsonb))
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.whatsapp_enqueue_message(text, text, text, text, jsonb) from public, anon;
grant execute on function public.whatsapp_enqueue_message(text, text, text, text, jsonb) to authenticated, service_role;
