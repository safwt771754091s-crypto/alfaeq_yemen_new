-- WhatsApp console RPCs (Alfaeq Yemen).
--
-- The Flutter automation console reads/writes through these RPCs instead of the
-- legacy platform-api edge function. Staff-only. Additive.

-- Bind a WhatsApp number to a merchant/store.
create or replace function public.set_whatsapp_connection(
  p_phone text,
  p_store_id text default null,
  p_merchant_uid text default null,
  p_auto_publish boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_uid text := auth.uid()::text;
  v_merchant text;
  v_id text;
begin
  if not (private.is_platform_staff() or auth.role() = 'service_role') then
    raise exception 'not_authorized';
  end if;

  v_merchant := coalesce(nullif(p_merchant_uid, ''), null);
  if v_merchant is null and p_store_id is not null then
    select owner_id into v_merchant from public.stores where id = p_store_id;
  end if;

  select id into v_id
    from public.whatsapp_connections
   where regexp_replace(phone, '[^0-9]', '', 'g') = regexp_replace(p_phone, '[^0-9]', '', 'g')
   limit 1;

  if v_id is null then
    v_id := 'wac-' || replace(gen_random_uuid()::text, '-', '');
    insert into public.whatsapp_connections(id, merchant_uid, phone, status, config)
    values (v_id, v_merchant, p_phone, 'active', jsonb_build_object('autoPublish', p_auto_publish, 'store_id', p_store_id));
  else
    update public.whatsapp_connections
       set merchant_uid = coalesce(v_merchant, merchant_uid),
           status = 'active',
           config = coalesce(config, '{}'::jsonb) || jsonb_build_object('autoPublish', p_auto_publish, 'store_id', p_store_id),
           updated_at = now()
     where id = v_id;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id, 'merchant_uid', v_merchant, 'auto_publish', p_auto_publish);
end;
$$;

revoke all on function public.set_whatsapp_connection(text, text, text, boolean) from public, anon;
grant execute on function public.set_whatsapp_connection(text, text, text, boolean) to authenticated, service_role;

create or replace function public.list_whatsapp_connections()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if not (private.is_platform_staff() or auth.role() = 'service_role') then
    raise exception 'not_authorized';
  end if;
  return jsonb_build_object('connections', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', c.id,
      'phone', c.phone,
      'merchantUid', c.merchant_uid,
      'storeId', (select s.id from public.stores s where s.owner_id = c.merchant_uid order by s.created_at limit 1),
      'autoPublish', coalesce((c.config->>'autoPublish')::boolean, false),
      'status', c.status
    ) order by c.created_at desc)
    from public.whatsapp_connections c
  ), '[]'::jsonb));
end;
$$;

revoke all on function public.list_whatsapp_connections() from public, anon;
grant execute on function public.list_whatsapp_connections() to authenticated, service_role;

-- Overload of list_whatsapp_imports returning the console shape.
drop function if exists public.list_whatsapp_imports(integer);

create or replace function public.list_whatsapp_imports(p_limit integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if not (private.is_platform_staff() or auth.role() = 'service_role') then
    raise exception 'not_authorized';
  end if;
  return jsonb_build_object('imports', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', i.id,
      'status', i.status,
      'merchantUid', i.merchant_uid,
      'phone', i.payload->>'phone',
      'text', i.payload->>'raw',
      'parsed', coalesce(i.payload->'parsed', '{}'::jsonb),
      'createdAt', i.created_at
    ) order by i.created_at desc)
    from (
      select * from public.whatsapp_product_imports
      order by created_at desc
      limit greatest(1, least(coalesce(p_limit, 50), 200))
    ) i
  ), '[]'::jsonb));
end;
$$;

revoke all on function public.list_whatsapp_imports(integer) from public, anon;
grant execute on function public.list_whatsapp_imports(integer) to authenticated, service_role;
