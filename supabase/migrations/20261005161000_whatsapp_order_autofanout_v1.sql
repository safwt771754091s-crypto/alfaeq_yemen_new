-- Automatic WhatsApp fan-out for orders (Alfaeq Yemen).
--
-- Extracts the auth-free fan-out into private.whatsapp_fanout and wires two
-- triggers:
--   * AFTER INSERT on orders        -> queue the invoice for the merchant(s)
--   * AFTER UPDATE of driver_id     -> queue a copy for the assigned driver
-- The public RPC keeps its authorization check and delegates to the internal
-- helper. Additive only.

-- ---------------------------------------------------------------------------
-- Internal fan-out (no auth check; callers are trusted paths)
-- ---------------------------------------------------------------------------
create or replace function private.whatsapp_fanout(
  p_order_id text,
  p_roles text[],
  p_include_customer boolean default false
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_order public.orders%rowtype;
  v_body text;
  v_inserted integer := 0;
  v_merchant_phones text[];
  v_driver_phone text;
  v_customer_phone text;
begin
  select * into v_order from public.orders where id = p_order_id;
  if not found then
    return 0;
  end if;

  v_body := public.get_order_invoice(p_order_id)->>'body';

  if 'merchant' = any (p_roles) then
    select array_remove(array_agg(distinct nullif(s.phone, '')), null)
      into v_merchant_phones
      from public.stores s
     where s.id = any (coalesce(v_order.merchant_ids, '{}'));
    if v_merchant_phones is not null then
      insert into public.whatsapp_notifications(order_id, recipient_role, to_phone, body, metadata)
      select p_order_id, 'merchant', phone, v_body, jsonb_build_object('invoice', true, 'auto', true)
        from unnest(v_merchant_phones) as phone;
      v_inserted := v_inserted + coalesce(array_length(v_merchant_phones, 1), 0);
    end if;
  end if;

  if 'driver' = any (p_roles) and v_order.driver_id is not null then
    select nullif(d.metadata->>'phone', '')
      into v_driver_phone
      from public.drivers d
     where d.uid = v_order.driver_id;
    if v_driver_phone is not null then
      insert into public.whatsapp_notifications(order_id, recipient_role, to_phone, body, metadata)
      values (p_order_id, 'driver', v_driver_phone, v_body, jsonb_build_object('invoice', true, 'auto', true));
      v_inserted := v_inserted + 1;
    end if;
  end if;

  if (p_include_customer or 'customer' = any (p_roles)) and v_order.customer_id is not null then
    select nullif(pa.metadata->>'phone', '')
      into v_customer_phone
      from public.platform_accounts pa
     where pa.owner_uid = v_order.customer_id
     order by pa.created_at
     limit 1;
    if v_customer_phone is not null then
      insert into public.whatsapp_notifications(order_id, recipient_role, to_phone, body, metadata)
      values (p_order_id, 'customer', v_customer_phone, v_body, jsonb_build_object('invoice', true, 'auto', true));
      v_inserted := v_inserted + 1;
    end if;
  end if;

  return v_inserted;
end;
$$;

revoke all on function private.whatsapp_fanout(text, text[], boolean) from public, anon, authenticated;

-- Public wrapper now delegates to the internal fan-out.
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
  v_queued integer;
  v_roles text[];
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

  v_roles := array['merchant', 'driver'];
  if p_include_customer then
    v_roles := array_append(v_roles, 'customer');
  end if;

  v_queued := private.whatsapp_fanout(p_order_id, v_roles, p_include_customer);

  return jsonb_build_object(
    'ok', true,
    'order_id', p_order_id,
    'queued', v_queued,
    'configured', (private.whatsapp_secret('WHATSAPP_ACCESS_TOKEN') is not null
                   and private.whatsapp_secret('WHATSAPP_PHONE_NUMBER_ID') is not null)
  );
end;
$$;

revoke all on function public.whatsapp_notify_order(text, boolean) from public, anon;
grant execute on function public.whatsapp_notify_order(text, boolean) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------
create or replace function private.trg_whatsapp_order_created()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  -- Never let a notification failure block order creation.
  begin
    perform private.whatsapp_fanout(new.id, array['merchant'], false);
  exception when others then
    null;
  end;
  return new;
end;
$$;

create or replace function private.trg_whatsapp_driver_assigned()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if new.driver_id is not null and (old.driver_id is null or old.driver_id is distinct from new.driver_id) then
    begin
      perform private.whatsapp_fanout(new.id, array['driver'], false);
    exception when others then
      null;
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists whatsapp_order_created on public.orders;
create trigger whatsapp_order_created
  after insert on public.orders
  for each row execute function private.trg_whatsapp_order_created();

drop trigger if exists whatsapp_driver_assigned on public.orders;
create trigger whatsapp_driver_assigned
  after update of driver_id on public.orders
  for each row execute function private.trg_whatsapp_driver_assigned();
