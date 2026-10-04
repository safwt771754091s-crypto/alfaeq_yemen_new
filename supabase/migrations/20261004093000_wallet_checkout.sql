-- Wallet checkout: pay for an order atomically from the in-app wallet.
-- Additive: adds one SECURITY DEFINER RPC; no existing object is altered.
--
-- The client is never granted EXECUTE on private.wallet_debit_internal, so the
-- debit must happen server-side. This wrapper creates the order (inventory
-- reserved) and debits the wallet inside one transaction; if the debit fails
-- (e.g. insufficient balance) the inner block is rolled back, leaving no order
-- behind. A client-supplied idempotency key makes checkout retries safe.

create or replace function public.create_order_paid(
  p_items jsonb,
  p_address text,
  p_idempotency_key text,
  p_currency text default 'YER'::text,
  p_latitude double precision default null,
  p_longitude double precision default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid text := auth.uid()::text;
  v_id text;
  v_existing text;
  v_total numeric;
  v_curr text;
  v_pay_currency text;
begin
  if v_uid is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if p_idempotency_key is null or length(btrim(p_idempotency_key)) < 8 then
    raise exception 'invalid_idempotency_key';
  end if;

  -- Idempotent retry: if this key already produced an order for this customer,
  -- return it instead of charging (or ordering) twice.
  select id into v_existing
  from public.orders
  where customer_id = v_uid and metadata ->> 'checkout_key' = p_idempotency_key
  limit 1;
  if v_existing is not null then
    return v_existing;
  end if;

  begin
    v_id := private.create_order_internal(p_items, p_address, 'wallet', p_latitude, p_longitude);

    select total, currency into v_total, v_curr from public.orders where id = v_id;
    if v_total is null or v_total <= 0 then
      raise exception 'invalid_order_total';
    end if;

    v_pay_currency := upper(coalesce(nullif(p_currency, ''), nullif(v_curr, ''), 'YER'));

    perform private.wallet_debit_internal(v_total, v_pay_currency, p_idempotency_key, 'order', v_id);

    update public.orders
    set payment_method = 'wallet',
        metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
          'payment_status', 'paid',
          'paid_at', now(),
          'checkout_key', p_idempotency_key,
          'wallet_currency', v_pay_currency,
          'wallet_amount', v_total
        )
    where id = v_id;

    return v_id;
  exception when others then
    -- Rolls back the order, its items, and the inventory reservation created
    -- inside this block so a failed payment leaves no dangling order.
    raise;
  end;
end
$function$;

revoke all on function public.create_order_paid(jsonb, text, text, text, double precision, double precision) from public, anon;
grant execute on function public.create_order_paid(jsonb, text, text, text, double precision, double precision) to authenticated;
