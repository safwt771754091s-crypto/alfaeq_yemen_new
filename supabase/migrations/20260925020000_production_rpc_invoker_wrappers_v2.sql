-- Align production RPC security with the private-schema architecture.
create schema if not exists private;

create or replace function private.redeem_merchant_invite_internal(p_token text)
returns boolean language plpgsql security definer set search_path=''
as $$
declare u text;
begin
  if auth.uid() is null or p_token is null or length(trim(p_token))=0 then raise exception 'invalid invite'; end if;
  u:=auth.uid()::text;
  update public.stores set owner_id=u,status='pending',updated_at=now()
   where invite_token=trim(p_token) and (owner_id is null or owner_id=u);
  if not found then raise exception 'invite not found or already used'; end if;
  update public.users set role='merchant',updated_at=now() where uid=u;
  return true;
end $$;

create or replace function private.transition_order_internal(
 p_order_id text,p_status text,p_delivery_status text default null)
returns boolean language plpgsql security definer set search_path=''
as $$
declare current_status text; uid text; merchant_authorized boolean:=false;
begin
 uid:=auth.uid()::text; if uid is null then raise exception 'not authenticated'; end if;
 select o.status into current_status from public.orders o where o.id=p_order_id for update;
 if current_status is null then raise exception 'order not found'; end if;
 select exists(select 1 from public.stores s join public.orders o on o.id=p_order_id
   where s.owner_id=uid and (s.id=o.merchant_id or s.id=any(o.merchant_ids))) into merchant_authorized;
 if not (uid=(select customer_id from public.orders where id=p_order_id)
   or uid=(select driver_id from public.orders where id=p_order_id)
   or merchant_authorized
   or exists(select 1 from public.users u where u.uid=uid and
      (coalesce(u.admin,false) or coalesce(u.owner,false) or coalesce(u.developer,false))))
 then raise exception 'not authorized'; end if;
 if merchant_authorized and not (
   (current_status='pending' and p_status in ('accepted','cancelled'))
   or (current_status='accepted' and p_status in ('preparing','cancelled'))
   or (current_status='preparing' and p_status='ready_for_pickup')
   or (current_status=p_status))
 then raise exception 'invalid merchant order transition'; end if;
 update public.orders set status=p_status,delivery_status=coalesce(p_delivery_status,delivery_status),updated_at=now()
  where id=p_order_id;
 return true;
end $$;

create or replace function private.wallet_credit_internal(
 p_amount numeric,p_currency text default 'YER',p_idempotency_key text default null,
 p_reference_type text default null,p_reference_id text default null)
returns numeric language plpgsql security definer set search_path=''
as $$
declare w public.wallets%rowtype; b numeric;
begin
 if auth.uid() is null or p_amount<=0 or p_idempotency_key is null then raise exception 'invalid wallet operation'; end if;
 select * into w from public.wallets where uid=auth.uid()::text and currency=upper(p_currency) for update;
 if w.uid is null then
   insert into public.wallets(uid,currency,status,available_balance,version)
   values(auth.uid()::text,upper(p_currency),'active',0,0) returning * into w;
 end if;
 if exists(select 1 from public.wallet_ledger where idempotency_key=p_idempotency_key) then return w.available_balance; end if;
 b:=w.available_balance+p_amount;
 update public.wallets set available_balance=b,version=version+1,updated_at=now()
  where uid=w.uid and currency=w.currency;
 insert into public.wallet_ledger(wallet_uid,user_id,entry_type,amount,balance_after,reference_type,reference_id,idempotency_key)
 values(w.uid,auth.uid()::text,'credit',p_amount,b,p_reference_type,p_reference_id,p_idempotency_key);
 return b;
end $$;

create or replace function private.wallet_debit_internal(
 p_amount numeric,p_currency text default 'YER',p_idempotency_key text default null,
 p_reference_type text default null,p_reference_id text default null)
returns numeric language plpgsql security definer set search_path=''
as $$
declare w public.wallets%rowtype; b numeric;
begin
 if auth.uid() is null or p_amount<=0 or p_idempotency_key is null then raise exception 'invalid wallet operation'; end if;
 select * into w from public.wallets where uid=auth.uid()::text and currency=upper(p_currency) for update;
 if w.uid is null or w.available_balance<p_amount then raise exception 'insufficient wallet balance'; end if;
 if exists(select 1 from public.wallet_ledger where idempotency_key=p_idempotency_key) then return w.available_balance; end if;
 b:=w.available_balance-p_amount;
 update public.wallets set available_balance=b,version=version+1,updated_at=now()
  where uid=w.uid and currency=w.currency;
 insert into public.wallet_ledger(wallet_uid,user_id,entry_type,amount,balance_after,reference_type,reference_id,idempotency_key)
 values(w.uid,auth.uid()::text,'debit',p_amount,b,p_reference_type,p_reference_id,p_idempotency_key);
 return b;
end $$;

create or replace function public.redeem_merchant_invite(p_token text)
returns boolean language sql security invoker set search_path=''
as $$ select private.redeem_merchant_invite_internal(p_token) $$;

create or replace function public.transition_order(p_order_id text,p_status text,p_delivery_status text default null)
returns boolean language sql security invoker set search_path=''
as $$ select private.transition_order_internal(p_order_id,p_status,p_delivery_status) $$;

create or replace function public.wallet_credit(p_amount numeric,p_currency text default 'YER',p_idempotency_key text default null,p_reference_type text default null,p_reference_id text default null)
returns numeric language sql security invoker set search_path=''
as $$ select private.wallet_credit_internal(p_amount,p_currency,p_idempotency_key,p_reference_type,p_reference_id) $$;

create or replace function public.wallet_debit(p_amount numeric,p_currency text default 'YER',p_idempotency_key text default null,p_reference_type text default null,p_reference_id text default null)
returns numeric language sql security invoker set search_path=''
as $$ select private.wallet_debit_internal(p_amount,p_currency,p_idempotency_key,p_reference_type,p_reference_id) $$;

create or replace function public.create_order(
 p_items jsonb,p_address text,p_payment_method text,
 p_latitude double precision default null,p_longitude double precision default null)
returns text language plpgsql security invoker set search_path=''
as $$
begin
 if (select auth.uid()) is null then raise exception 'authentication_required' using errcode='28000'; end if;
 return private.create_order_internal(p_items,p_address,p_payment_method,p_latitude,p_longitude);
end $$;

create or replace function public.assign_order_driver(p_order_id text,p_driver_id text)
returns boolean language sql security invoker set search_path=''
as $$ select private.assign_order_driver(p_order_id,p_driver_id)::boolean $$;

grant usage on schema private to authenticated;
grant execute on function private.redeem_merchant_invite_internal(text) to authenticated;
grant execute on function private.transition_order_internal(text,text,text) to authenticated;
grant execute on function private.wallet_credit_internal(numeric,text,text,text,text) to authenticated;
grant execute on function private.wallet_debit_internal(numeric,text,text,text,text) to authenticated;

revoke execute on function public.redeem_merchant_invite(text) from public,anon;
revoke execute on function public.transition_order(text,text,text) from public,anon;
revoke execute on function public.wallet_credit(numeric,text,text,text,text) from public,anon;
revoke execute on function public.wallet_debit(numeric,text,text,text,text) from public,anon;
revoke execute on function public.create_order(jsonb,text,text,double precision,double precision) from public,anon;
revoke execute on function public.assign_order_driver(text,text) from public,anon;

grant execute on function public.redeem_merchant_invite(text) to authenticated;
grant execute on function public.transition_order(text,text,text) to authenticated;
grant execute on function public.wallet_credit(numeric,text,text,text,text) to authenticated;
grant execute on function public.wallet_debit(numeric,text,text,text,text) to authenticated;
grant execute on function public.create_order(jsonb,text,text,double precision,double precision) to authenticated;
grant execute on function public.assign_order_driver(text,text) to authenticated;
