-- Online payment gateway layer.
--
-- Adds a provider-agnostic payment lifecycle on top of the existing commerce
-- core (create_order_internal). Nothing here touches the wallet: online money
-- arrives from an external PSP, and orders are only marked paid by the
-- service-role edge function `payment-gateway` after the PSP confirms.

-- Staff may record manual payments; the service role bypasses RLS anyway.
drop policy if exists payments_staff_insert on public.payments;
create policy payments_staff_insert on public.payments
  for insert to authenticated
  with check (private.is_platform_staff());

-- Create an order that will be paid online. Mirrors create_order but tags the
-- order as `online` + `pending` so it is never treated as cash-on-delivery.
create or replace function public.create_pending_order(
  p_items jsonb,
  p_address text,
  p_provider text,
  p_display_currency text default 'YER',
  p_latitude double precision default null,
  p_longitude double precision default null
) returns text
language plpgsql
security definer
set search_path to 'pg_catalog','public','auth','private'
as $function$
declare
  v_id text;
  v_provider text := lower(btrim(coalesce(p_provider, 'manual')));
begin
  if v_provider not in ('manual', 'stripe', 'paypal') then
    raise exception 'unsupported_provider';
  end if;

  v_id := private.create_order_internal(p_items, p_address, 'online', p_latitude, p_longitude, p_display_currency);

  update public.orders
  set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'payment_status', 'pending',
        'payment_provider', v_provider
      ),
      updated_at = now()
  where id = v_id;

  return v_id;
end
$function$;

revoke all on function public.create_pending_order(jsonb, text, text, text, double precision, double precision) from public, anon;
grant execute on function public.create_pending_order(jsonb, text, text, text, double precision, double precision) to authenticated;

-- Store the provider's own reference (PaymentIntent id / PayPal order id) on
-- the order right after the intent is created. Service-role only.
create or replace function public.attach_payment_provider(
  p_order_id text,
  p_provider text,
  p_provider_ref text
) returns void
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $function$
begin
  update public.orders
  set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'payment_provider', lower(btrim(coalesce(p_provider, 'manual'))),
        'payment_provider_ref', p_provider_ref
      ),
      updated_at = now()
  where id = p_order_id;
end
$function$;

revoke all on function public.attach_payment_provider(text, text, text) from public, anon, authenticated;

-- Mark an order paid and record the payment row. Idempotent. Service-role only:
-- a client must never be able to declare its own order paid.
create or replace function public.mark_order_paid(
  p_order_id text,
  p_provider text,
  p_provider_ref text,
  p_amount numeric,
  p_currency text,
  p_metadata jsonb default '{}'::jsonb
) returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $function$
declare
  v_order public.orders%rowtype;
  v_provider text := lower(btrim(coalesce(p_provider, 'manual')));
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.id is null then
    raise exception 'order_not_found';
  end if;

  if coalesce(v_order.metadata ->> 'payment_status', '') = 'paid' then
    return true;
  end if;

  insert into public.payments(
    id, order_id, customer_id, provider_id, amount, currency, status, metadata, created_at, updated_at
  ) values (
    'pay_' || replace(gen_random_uuid()::text, '-', ''),
    p_order_id, v_order.customer_id, v_provider,
    coalesce(p_amount, v_order.total), upper(btrim(coalesce(p_currency, v_order.currency, 'USD'))),
    'paid',
    coalesce(p_metadata, '{}'::jsonb) || jsonb_build_object('provider_ref', p_provider_ref),
    now(), now()
  );

  update public.orders
  set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'payment_status', 'paid',
        'paid_at', now(),
        'payment_provider', v_provider,
        'payment_ref', p_provider_ref
      ),
      updated_at = now()
  where id = p_order_id;

  return true;
end
$function$;

revoke all on function public.mark_order_paid(text, text, text, numeric, text, jsonb) from public, anon, authenticated;
