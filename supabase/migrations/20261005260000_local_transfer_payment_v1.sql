-- Local bank / e-wallet transfer with receipt upload + staff approval.
--
-- The most practical "real" payment for Yemen: the customer transfers to the
-- platform's account, uploads the receipt, and staff confirm it. This reuses
-- the existing payment lifecycle (orders.metadata.payment_status + payments
-- rows) so a locally-paid order looks identical to a card-paid one.

-- Local transfers are an allowed pending-order provider.
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
  if v_provider not in ('manual', 'stripe', 'paypal', 'local_transfer') then
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

-- Customer: submit a transfer receipt for review.
create or replace function public.submit_local_payment(
  p_order_id text,
  p_reference text,
  p_receipt_url text,
  p_note text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','auth'
as $function$
declare
  v_uid text := auth.uid()::text;
  v_order public.orders%rowtype;
  v_ref text := btrim(coalesce(p_reference, ''));
  v_receipt text := btrim(coalesce(p_receipt_url, ''));
begin
  if v_uid is null then
    raise exception 'authentication_required';
  end if;
  if v_ref = '' then
    raise exception 'reference_required';
  end if;
  if v_receipt = '' then
    raise exception 'receipt_required';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.id is null then
    raise exception 'order_not_found';
  end if;
  if v_order.customer_id is distinct from v_uid then
    raise exception 'forbidden';
  end if;
  if coalesce(v_order.metadata ->> 'payment_status', '') = 'paid' then
    raise exception 'already_paid';
  end if;

  perform public.attach_payment_provider(p_order_id, 'local_transfer', v_ref);

  update public.orders
  set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'payment_status', 'awaiting_review',
        'transfer_reference', v_ref,
        'receipt_url', v_receipt,
        'transfer_note', nullif(btrim(coalesce(p_note, '')), '')
      ),
      updated_at = now()
  where id = p_order_id;

  -- No payments row yet: approval runs mark_order_paid, which writes the single
  -- authoritative 'paid' record. The submission itself lives on the order.
  return jsonb_build_object('status', 'awaiting_review', 'orderId', p_order_id, 'reference', v_ref);
end
$function$;

revoke all on function public.submit_local_payment(text, text, text, text) from public, anon;
grant execute on function public.submit_local_payment(text, text, text, text) to authenticated;

-- Staff: approve or reject a submitted transfer.
create or replace function public.approve_local_payment(
  p_order_id text,
  p_approve boolean,
  p_note text default null
) returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog','public','auth','private'
as $function$
declare
  v_uid text := auth.uid()::text;
  v_order public.orders%rowtype;
begin
  if not private.is_platform_staff() then
    raise exception 'forbidden';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.id is null then
    raise exception 'order_not_found';
  end if;

  if p_approve then
    perform public.mark_order_paid(
      p_order_id,
      'local_transfer',
      coalesce(v_order.metadata ->> 'transfer_reference', ''),
      v_order.total,
      upper(btrim(coalesce(v_order.currency, 'USD'))),
      jsonb_build_object(
        'approved_by', v_uid,
        'approved_at', now(),
        'receipt_url', v_order.metadata ->> 'receipt_url',
        'review_note', nullif(btrim(coalesce(p_note, '')), '')
      )
    );
    return true;
  end if;

  update public.orders
  set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'payment_status', 'rejected',
        'review_note', nullif(btrim(coalesce(p_note, '')), ''),
        'reviewed_by', v_uid,
        'reviewed_at', now()
      ),
      updated_at = now()
  where id = p_order_id;

  return false;
end
$function$;

revoke all on function public.approve_local_payment(text, boolean, text) from public, anon;
grant execute on function public.approve_local_payment(text, boolean, text) to authenticated;
