-- WhatsApp product-import lifecycle (Alfaeq Yemen).
--
-- Inbound merchant messages are ingested by the whatsapp-webhook edge function,
-- parsed by AI, and either auto-published or held for confirmation. These RPCs
-- are the single write path so the Flutter UI and the webhook agree.
--
-- Additive only.

-- ---------------------------------------------------------------------------
-- Ingest an inbound message and open an import record
-- ---------------------------------------------------------------------------
create or replace function public.whatsapp_ingest_message(
  p_phone text,
  p_message text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_conn public.whatsapp_connections%rowtype;
  v_merchant_uid text;
  v_message_id text;
  v_import_id text;
begin
  if not (auth.role() = 'service_role' or private.is_platform_staff()) then
    raise exception 'not_authorized';
  end if;

  select * into v_conn
    from public.whatsapp_connections
   where regexp_replace(phone, '[^0-9]', '', 'g') = regexp_replace(p_phone, '[^0-9]', '', 'g')
   order by created_at
   limit 1;

  v_merchant_uid := coalesce(v_conn.merchant_uid, '');

  v_message_id := 'wam-' || replace(gen_random_uuid()::text, '-', '');
  insert into public.whatsapp_messages(id, merchant_uid, connection_id, direction, phone, message, payload)
  values (v_message_id, nullif(v_merchant_uid, ''), v_conn.id, 'inbound', p_phone, p_message, coalesce(p_payload, '{}'::jsonb));

  v_import_id := 'wai-' || replace(gen_random_uuid()::text, '-', '');
  insert into public.whatsapp_product_imports(id, merchant_uid, status, source, payload)
  values (
    v_import_id,
    nullif(v_merchant_uid, ''),
    'received',
    'whatsapp',
    jsonb_build_object(
      'raw', p_message,
      'phone', p_phone,
      'connection_id', v_conn.id,
      'auto_publish', coalesce((v_conn.config->>'autoPublish')::boolean, false)
    )
  );

  return jsonb_build_object(
    'message_id', v_message_id,
    'import_id', v_import_id,
    'connection_id', v_conn.id,
    'merchant_uid', v_merchant_uid,
    'auto_publish', coalesce((v_conn.config->>'autoPublish')::boolean, false)
  );
end;
$$;

revoke all on function public.whatsapp_ingest_message(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.whatsapp_ingest_message(text, text, jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- Attach the AI parse result to an import
-- ---------------------------------------------------------------------------
create or replace function public.whatsapp_set_import_parsed(
  p_import_id text,
  p_parsed jsonb
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if not (auth.role() = 'service_role' or private.is_platform_staff()) then
    raise exception 'not_authorized';
  end if;
  update public.whatsapp_product_imports
     set status = 'parsed',
         payload = coalesce(payload, '{}'::jsonb) || jsonb_build_object('parsed', coalesce(p_parsed, '{}'::jsonb)),
         updated_at = now()
   where id = p_import_id;
end;
$$;

revoke all on function public.whatsapp_set_import_parsed(text, jsonb) from public, anon, authenticated;
grant execute on function public.whatsapp_set_import_parsed(text, jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- Confirm (and optionally publish) an import into a real product
-- ---------------------------------------------------------------------------
create or replace function public.confirm_whatsapp_import(
  p_import_id text,
  p_name text,
  p_price numeric,
  p_stock numeric,
  p_publish boolean default false,
  p_section_id text default 'markets',
  p_store_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_import public.whatsapp_product_imports%rowtype;
  v_uid text;
  v_owner text;
  v_store text;
  v_product_id text;
  v_unit record;
begin
  v_uid := auth.uid()::text;

  select * into v_import from public.whatsapp_product_imports where id = p_import_id;
  if not found then
    raise exception 'import_not_found';
  end if;

  v_owner := coalesce(v_import.merchant_uid, v_uid);
  v_store := p_store_id;

  if v_store is null then
    select id into v_store
      from public.stores
     where owner_id = v_owner
     order by created_at
     limit 1;
  end if;
  if v_store is null then
    raise exception 'store_not_found_for_merchant';
  end if;

  if not (
    private.is_platform_staff()
    or exists (select 1 from public.stores s where s.id = v_store and s.owner_id = v_uid)
  ) then
    raise exception 'not_authorized';
  end if;

  v_product_id := 'prod-wa-' || replace(gen_random_uuid()::text, '-', '');

  insert into public.products(
    id, store_id, section_id, owner_id, name, description, price, currency, stock, stock_base,
    sale_unit, unit_label, base_unit, unit_scale, step_base, min_order_base,
    sold_quantity, sold_quantity_base, status, metadata
  ) values (
    v_product_id, v_store, coalesce(nullif(p_section_id, ''), 'markets'), v_owner,
    coalesce(nullif(p_name, ''), 'صنف واتساب'), '', greatest(coalesce(p_price, 0), 0), 'USD',
    greatest(coalesce(p_stock, 0), 0), greatest(coalesce(p_stock, 0), 0),
    'piece', 'قطعة', 'piece', 1, 1, 1,
    0, 0, case when p_publish then 'active' else 'draft' end,
    jsonb_build_object('source', 'whatsapp_ai', 'import_id', p_import_id, 'published', p_publish)
  );

  update public.whatsapp_product_imports
     set status = case when p_publish then 'published' else 'confirmed' end,
         payload = coalesce(payload, '{}'::jsonb) || jsonb_build_object('product_id', v_product_id),
         updated_at = now()
   where id = p_import_id;

  return jsonb_build_object('ok', true, 'product_id', v_product_id, 'published', p_publish, 'store_id', v_store);
end;
$$;

revoke all on function public.confirm_whatsapp_import(text, text, numeric, numeric, boolean, text, text) from public, anon;
grant execute on function public.confirm_whatsapp_import(text, text, numeric, numeric, boolean, text, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Staff/service listing for the automation console
-- ---------------------------------------------------------------------------
create or replace function public.list_whatsapp_imports(p_limit integer default 50)
returns setof public.whatsapp_product_imports
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select *
    from public.whatsapp_product_imports
   where private.is_platform_staff() or auth.role() = 'service_role'
   order by created_at desc
   limit greatest(1, least(coalesce(p_limit, 50), 200))
$$;

revoke all on function public.list_whatsapp_imports(integer) from public, anon;
grant execute on function public.list_whatsapp_imports(integer) to authenticated, service_role;
