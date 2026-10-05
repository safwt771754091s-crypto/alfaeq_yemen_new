-- Recipient fallback for WhatsApp order fan-out.
--
-- The order-created trigger resolved merchant phone numbers only from
-- public.stores.phone, but the production store has no phone and no owner_id,
-- so every order silently queued zero notifications. This adds a documented
-- fallback chain and a staff-only setter so a store phone can be recorded from
-- the merchant console. Additive only.

-- ---------------------------------------------------------------------------
-- Staff-only store phone setter (merchants console writes through this).
-- ---------------------------------------------------------------------------
create or replace function public.set_store_contact(
  p_store_id text,
  p_phone text default null,
  p_merchant_uid text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_uid text := auth.uid()::text;
  v_phone text := nullif(btrim(coalesce(p_phone, '')), '');
begin
  if p_store_id is null or btrim(p_store_id) = '' then
    raise exception 'store_id_required';
  end if;
  if not (
    private.is_platform_staff()
    or exists (select 1 from public.stores s where s.id = p_store_id and s.owner_id = v_uid)
  ) then
    raise exception 'not_authorized';
  end if;

  update public.stores
     set phone = v_phone,
         owner_id = coalesce(nullif(btrim(coalesce(p_merchant_uid, '')), ''), owner_id),
         updated_at = now()
   where id = p_store_id;

  if not found then raise exception 'store_not_found'; end if;

  return jsonb_build_object('ok', true, 'store_id', p_store_id, 'phone', v_phone);
end;
$$;

revoke all on function public.set_store_contact(text, text, text) from public, anon;
grant execute on function public.set_store_contact(text, text, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Fan-out with recipient fallbacks.
--   merchant: stores.phone -> users.phone(owner) -> store contact in settings
--   driver:   drivers.metadata->>'phone' -> users.phone
--   customer: platform_accounts.metadata->>'phone' -> users.phone
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
    select array_remove(array_agg(distinct phone), null)
      into v_merchant_phones
      from (
        -- 1) explicit store contact numbers
        select nullif(s.phone, '') as phone
          from public.stores s
         where s.id = any (coalesce(v_order.merchant_ids, '{}'))
        union all
        -- 2) store owner account numbers
        select nullif(u.phone, '') as phone
          from public.stores s
          join public.users u on u.uid = s.owner_id
         where s.id = any (coalesce(v_order.merchant_ids, '{}'))
        union all
        -- 3) operator-configured fallback contact (settings.id = 'store_contact')
        select nullif(coalesce(sv.value #>> '{phone}', ''), '') as phone
          from public.settings sv
         where sv.id = 'store_contact'
      ) t;
    if v_merchant_phones is not null then
      insert into public.whatsapp_notifications(order_id, recipient_role, to_phone, body, metadata)
      select p_order_id, 'merchant', phone, v_body, jsonb_build_object('invoice', true, 'auto', true)
        from unnest(v_merchant_phones) as phone;
      v_inserted := v_inserted + coalesce(array_length(v_merchant_phones, 1), 0);
    end if;
  end if;

  if 'driver' = any (p_roles) and v_order.driver_id is not null then
    select coalesce(
             nullif(d.metadata->>'phone', ''),
             nullif(u.phone, '')
           )
      into v_driver_phone
      from public.drivers d
      left join public.users u on u.uid = d.uid
     where d.uid = v_order.driver_id;
    if v_driver_phone is not null then
      insert into public.whatsapp_notifications(order_id, recipient_role, to_phone, body, metadata)
      values (p_order_id, 'driver', v_driver_phone, v_body, jsonb_build_object('invoice', true, 'auto', true));
      v_inserted := v_inserted + 1;
    end if;
  end if;

  if (p_include_customer or 'customer' = any (p_roles)) and v_order.customer_id is not null then
    select coalesce(
             nullif(pa.metadata->>'phone', ''),
             nullif(u.phone, '')
           )
      into v_customer_phone
      from public.platform_accounts pa
      left join public.users u on u.uid = pa.owner_uid
     where pa.owner_uid = v_order.customer_id
     order by pa.created_at
     limit 1;
    if v_customer_phone is null then
      select nullif(phone, '') into v_customer_phone from public.users where uid = v_order.customer_id;
    end if;
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
