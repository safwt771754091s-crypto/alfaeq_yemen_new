-- In-app notifications for the order lifecycle (Alfaeq Yemen).
--
-- The `notifications` table and its live UI existed, but nothing ever inserted
-- a row, so customers, merchants and drivers never received in-app updates.
-- These triggers generate them on order creation, assignment and delivery.
-- Location-only pings (driver_update_order writes driver_location on every
-- update) are deliberately ignored so they do not spam the customer.

create or replace function private.notify_user(
  p_user_id text,
  p_type text,
  p_title text,
  p_body text,
  p_data jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_user_id is null or btrim(p_user_id) = '' then
    return;
  end if;
  insert into public.notifications(user_id, type, title, body, data)
  values (p_user_id, p_type, p_title, p_body, coalesce(p_data, '{}'::jsonb));
end;
$$;

create or replace function private.trg_order_notifications()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_amount text := to_char(coalesce(new.display_total, new.total, 0), 'FM999999990.##');
  v_cur text := coalesce(nullif(new.display_currency, ''), nullif(new.currency, ''), 'USD');
  v_msg text;
  v_mid text;
begin
  if tg_op = 'INSERT' then
    perform private.notify_user(
      new.customer_id, 'order', 'تم استلام طلبك',
      'طلبك رقم ' || new.id || ' قيد المعالجة. الإجمالي: ' || v_amount || ' ' || v_cur,
      jsonb_build_object('order_id', new.id, 'status', new.status)
    );
    if new.merchant_id is not null then
      perform private.notify_user(
        new.merchant_id, 'order', 'طلب جديد',
        'وصلك طلب جديد رقم ' || new.id || ' بقيمة ' || v_amount || ' ' || v_cur,
        jsonb_build_object('order_id', new.id, 'status', new.status)
      );
    end if;
    if new.merchant_ids is not null then
      foreach v_mid in array new.merchant_ids loop
        if v_mid is not null and v_mid is distinct from new.merchant_id then
          perform private.notify_user(
            v_mid, 'order', 'طلب جديد',
            'وصلك طلب جديد رقم ' || new.id,
            jsonb_build_object('order_id', new.id, 'status', new.status)
          );
        end if;
      end loop;
    end if;
    return new;
  end if;

  -- Ignore updates that only move the driver's location.
  if new.status is not distinct from old.status
     and new.delivery_status is not distinct from old.delivery_status
     and new.driver_id is not distinct from old.driver_id then
    return new;
  end if;

  if new.status = 'cancelled' and old.status is distinct from 'cancelled' then
    v_msg := 'تم إلغاء طلبك رقم ' || new.id || '.';
  elsif new.status = 'delivered' or new.delivery_status = 'delivered' then
    v_msg := 'تم تسليم طلبك رقم ' || new.id || '. شكراً لاستخدامك الفائق يمن.';
  elsif new.driver_id is distinct from old.driver_id and new.driver_id is not null then
    v_msg := 'تم تعيين مندوب لطلبك رقم ' || new.id || '.';
  elsif new.delivery_status is distinct from old.delivery_status then
    v_msg := 'تحديث حالة طلبك رقم ' || new.id || ': ' || coalesce(new.delivery_status, '');
  elsif new.status is distinct from old.status then
    v_msg := 'تحديث حالة طلبك رقم ' || new.id || ': ' || coalesce(new.status, '');
  end if;

  if v_msg is not null then
    perform private.notify_user(
      new.customer_id, 'order', 'تحديث الطلب', v_msg,
      jsonb_build_object('order_id', new.id, 'status', new.status, 'delivery_status', new.delivery_status)
    );
  end if;

  if new.driver_id is distinct from old.driver_id and new.driver_id is not null then
    perform private.notify_user(
      new.driver_id, 'delivery', 'طلب جديد للتو',
      'تم تعيينك لتوصيل الطلب رقم ' || new.id || '.',
      jsonb_build_object('order_id', new.id)
    );
  end if;

  if (new.status = 'delivered' or new.delivery_status = 'delivered')
     and not (old.status = 'delivered' or old.delivery_status = 'delivered') then
    if new.merchant_id is not null then
      perform private.notify_user(
        new.merchant_id, 'order', 'تم تسليم طلب',
        'تم تسليم الطلب رقم ' || new.id || ' بنجاح.',
        jsonb_build_object('order_id', new.id)
      );
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists order_notifications on public.orders;
create trigger order_notifications
  after insert or update on public.orders
  for each row execute function private.trg_order_notifications();
