-- Alfaeq Yemen: controlled merchant inventory adjustments
create or replace function public.adjust_product_inventory(
  p_product_id text,
  p_new_stock numeric
) returns table(product_id text, stock_before numeric, stock_after numeric, quantity_delta numeric)
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid text := auth.uid()::text;
  p products%rowtype;
  v_before numeric;
  v_delta numeric;
  v_delta_base numeric;
  v_store_owner text;
begin
  if v_uid is null then raise exception 'authentication_required' using errcode='28000'; end if;
  if p_product_id is null or btrim(p_product_id)='' then raise exception 'product_id_required'; end if;
  if p_new_stock is null or p_new_stock < 0 then raise exception 'invalid_stock'; end if;

  select * into p from products where id=p_product_id for update;
  if not found then raise exception 'product_not_found'; end if;

  select owner_id into v_store_owner from stores where id=p.store_id;
  if not (
    v_store_owner=v_uid
    or exists(select 1 from users u where u.uid=v_uid and
      (coalesce(u.admin,false) or coalesce(u.owner,false) or coalesce(u.developer,false)))
  ) then
    raise exception 'not_authorized';
  end if;

  v_before:=coalesce(p.stock,0);
  v_delta:=p_new_stock-v_before;
  v_delta_base:=v_delta*coalesce(p.unit_scale,1);

  if v_delta=0 then
    product_id:=p.id; stock_before:=v_before; stock_after:=v_before; quantity_delta:=0; return next; return;
  end if;

  update products
  set stock=p_new_stock,
      stock_base=greatest(0,coalesce(p.stock_base,0)+v_delta_base),
      updated_at=now()
  where id=p.id;

  insert into inventory_movements(
    product_id,quantity,quantity_base,stock_before_base,stock_after_base,movement_type,metadata
  ) values (
    p.id,abs(v_delta),abs(v_delta_base),coalesce(p.stock_base,p.stock),
    greatest(0,coalesce(p.stock_base,p.stock)+v_delta_base),
    case when v_delta>0 then 'restock' else 'adjustment' end,
    jsonb_build_object('source','merchant_inventory_adjustment','actor_id',v_uid,'delta',v_delta)
  );

  product_id:=p.id; stock_before:=v_before; stock_after:=p_new_stock; quantity_delta:=v_delta; return next;
end;
$function$;

revoke all on function public.adjust_product_inventory(text,numeric) from public,anon;
grant execute on function public.adjust_product_inventory(text,numeric) to authenticated;