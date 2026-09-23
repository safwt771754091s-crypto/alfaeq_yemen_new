create or replace function public.transition_order(
  p_order_id text,
  p_status text,
  p_delivery_status text default null
) returns boolean
language plpgsql
security definer
set search_path=''
as $function$
declare
  current_status text;
  current_delivery text;
  uid text;
  merchant_authorized boolean := false;
begin
  uid := auth.uid()::text;
  if uid is null then raise exception 'not authenticated'; end if;
  select status, delivery_status into current_status, current_delivery
    from public.orders where id = p_order_id for update;
  if current_status is null then raise exception 'order not found'; end if;
  select exists(
    select 1 from public.stores s
    join public.orders o on o.id = p_order_id
    where s.owner_id = uid and (s.id = o.merchant_id or s.id = any(o.merchant_ids))
  ) into merchant_authorized;
  if not (
    uid = (select customer_id from public.orders where id=p_order_id)
    or uid = (select driver_id from public.orders where id=p_order_id)
    or merchant_authorized
    or exists(select 1 from public.users u where u.uid=uid and
      (coalesce(u.admin,false) or coalesce(u.owner,false) or coalesce(u.developer,false)))
  ) then raise exception 'not authorized'; end if;
  if merchant_authorized and not (
    (current_status='pending' and p_status in ('accepted','cancelled'))
    or (current_status='accepted' and p_status in ('preparing','cancelled'))
    or (current_status='preparing' and p_status='ready_for_pickup')
    or current_status=p_status
  ) then raise exception 'invalid merchant order transition'; end if;
  update public.orders set status=p_status,
    delivery_status=coalesce(p_delivery_status,delivery_status), updated_at=now()
    where id=p_order_id;
  return true;
end
$function$;