create or replace function private.enqueue_automation_inbox_event(
  p_event_type text,
  p_aggregate_type text,
  p_aggregate_id text,
  p_data jsonb,
  p_event_id text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  v_event_id text := coalesce(
    nullif(p_event_id, ''),
    p_event_type || ':' || coalesce(nullif(p_aggregate_id,''), md5(coalesce(p_data,'{}'::jsonb)::text)) || ':' || extract(epoch from clock_timestamp())::bigint::text || ':' || substr(md5(random()::text),1,8)
  );
  v_id uuid;
begin
  insert into public.automation_event_inbox(
    event_id, source, version, event_type, occurred_at, data
  )
  values(
    v_event_id,
    'supabase',
    1,
    p_event_type,
    now(),
    jsonb_build_object(
      'aggregateType', p_aggregate_type,
      'aggregateId', p_aggregate_id,
      'data', coalesce(p_data,'{}'::jsonb)
    )
  )
  on conflict (event_id) do nothing
  returning id into v_id;
  return v_id;
end;
$function$;

create or replace function private.enqueue_domain_automation_event()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  new_json jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) else null end;
  old_json jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) else null end;
  record_json jsonb;
  previous_json jsonb;
  aggregate_id text;
  aggregate_type text;
  event_type text;
  event_id text;
begin
  record_json := coalesce(new_json, old_json, '{}'::jsonb)
    - 'token_hash' - 'shared_secret' - 'password' - 'access_token'
    - 'refresh_token' - 'api_key' - 'service_role_key' - 'private_key';
  previous_json := case when old_json is null then null else old_json
    - 'token_hash' - 'shared_secret' - 'password' - 'access_token'
    - 'refresh_token' - 'api_key' - 'service_role_key' - 'private_key' end;

  if tg_table_name = 'chat_messages' then
    record_json := record_json - 'body';
    previous_json := case when previous_json is null then null else previous_json - 'body' end;
  end if;

  aggregate_id := coalesce(
    record_json->>'id', record_json->>'uid', record_json->>'account_id',
    record_json->>'thread_id', record_json->>'wallet_uid',
    old_json->>'id', old_json->>'uid'
  );
  if aggregate_id is null or aggregate_id = '' then
    aggregate_id := md5(coalesce(record_json::text, old_json::text, ''));
  end if;

  aggregate_type := case tg_table_name
    when 'sections' then 'section'
    when 'drivers' then 'driver'
    when 'delivery_events' then 'delivery_event'
    when 'payments' then 'payment'
    when 'reviews' then 'review'
    when 'wallet_transactions' then 'wallet_transaction'
    when 'wallet_operations' then 'wallet_operation'
    when 'wallet_ledger' then 'wallet_ledger'
    when 'merchant_invites' then 'merchant_invite'
    when 'invoices' then 'invoice'
    when 'settlements' then 'settlement'
    when 'chat_threads' then 'chat_thread'
    when 'chat_members' then 'chat_member'
    when 'chat_messages' then 'chat_message'
    when 'platform_accounts' then 'platform_account'
    when 'account_members' then 'account_member'
    else tg_table_name
  end;

  event_type := aggregate_type || case
    when tg_op = 'INSERT' then '.created'
    when tg_op = 'UPDATE' then '.updated'
    when tg_op = 'DELETE' then '.deleted'
    else '.changed'
  end;

  event_id := event_type || ':' || aggregate_id || ':' ||
    coalesce(record_json->>'updated_at', record_json->>'created_at', extract(epoch from clock_timestamp())::text);

  perform private.enqueue_automation_inbox_event(
    event_type,
    aggregate_type,
    aggregate_id,
    jsonb_build_object(
      'source','supabase',
      'table',tg_table_name,
      'operation',tg_op,
      'record',record_json,
      'previous',previous_json
    ),
    event_id
  );

  return coalesce(new, old);
end;
$function$;

create or replace function private.trg_enqueue_inventory_event()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  v_event_type text;
begin
  v_event_type := case
    when new.movement_type in ('sale_reservation','reservation') then 'inventory.reserved'
    when new.movement_type in ('sale_release','reservation_release','release') then 'inventory.released'
    else 'inventory.adjusted'
  end;

  perform private.enqueue_automation_inbox_event(
    v_event_type,
    'inventory',
    new.product_id,
    jsonb_build_object(
      'source','supabase',
      'table','inventory_movements',
      'operation','INSERT',
      'record',to_jsonb(new),
      'order_id',new.order_id,
      'product_id',new.product_id,
      'movement_type',new.movement_type
    ),
    'inventory:' || new.id::text || ':v1'
  );
  return new;
end;
$function$;

create or replace function private.trg_enqueue_order_update_event()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
begin
  perform private.enqueue_automation_inbox_event(
    'order.updated',
    'order',
    new.id,
    jsonb_build_object('source','supabase','table','orders','operation','UPDATE','record',to_jsonb(new),'previous',to_jsonb(old)),
    'order.updated:' || new.id::text || ':' || coalesce(new.updated_at::text, extract(epoch from clock_timestamp())::text)
  );
  return new;
end;
$function$;

create or replace function private.trg_enqueue_product_event()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
begin
  perform private.enqueue_automation_inbox_event(
    case when tg_op = 'INSERT' then 'product.created' else 'product.updated' end,
    'product',
    new.id,
    jsonb_build_object('source','supabase','table','products','operation',tg_op,'record',to_jsonb(new)),
    case when tg_op = 'INSERT' then 'product.created:' || new.id::text || ':v1'
         else 'product.updated:' || new.id::text || ':' || coalesce(new.updated_at::text, extract(epoch from clock_timestamp())::text)
    end
  );
  return new;
end;
$function$;

create or replace function private.trg_enqueue_store_event()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
begin
  perform private.enqueue_automation_inbox_event(
    case when tg_op = 'INSERT' then 'store.created' else 'store.updated' end,
    'store',
    new.id,
    jsonb_build_object('source','supabase','table','stores','operation',tg_op,'record',to_jsonb(new)),
    case when tg_op = 'INSERT' then 'store.created:' || new.id::text || ':v1'
         else 'store.updated:' || new.id::text || ':' || coalesce(new.updated_at::text, extract(epoch from clock_timestamp())::text)
    end
  );
  return new;
end;
$function$;

create or replace function public.enqueue_content_automation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  aggregate_id text := coalesce(new.id, old.id);
  aggregate_type text := case when tg_table_name = 'promotions' then 'promotion' else 'site_update' end;
  event_type text := case
    when tg_op = 'INSERT' then aggregate_type || '.created'
    when tg_op = 'UPDATE' then aggregate_type || '.updated'
    else aggregate_type || '.deleted'
  end;
begin
  perform private.enqueue_automation_inbox_event(
    event_type,
    aggregate_type,
    aggregate_id,
    jsonb_build_object(
      'source','supabase',
      'table',tg_table_name,
      'operation',tg_op,
      'record',case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end,
      'previous',case when tg_op='UPDATE' then to_jsonb(old) else null end
    ),
    event_type || ':' || aggregate_id || ':' ||
      coalesce((case when tg_op='DELETE' then old else new end).updated_at::text,
               (case when tg_op='DELETE' then old else new end).created_at::text,
               extract(epoch from clock_timestamp())::text)
  );
  return coalesce(new, old);
end;
$function$;

drop trigger if exists automation_event_inbox_worker_dispatch on public.automation_event_inbox;
create trigger automation_event_inbox_worker_dispatch
after insert on public.automation_event_inbox
for each row execute function private.trigger_automation_worker_inbox();

drop trigger if exists automation_worker_dispatch on public.automation_events;
