-- Restrict privileged SECURITY DEFINER RPCs to signed-in clients.
-- The functions retain SECURITY DEFINER because they implement controlled server-side mutations;
-- anonymous/public execution is not required by the Flutter application.

revoke execute on function public.redeem_merchant_invite(text) from public, anon;
revoke execute on function public.transition_order(text,text,text) from public, anon;
revoke execute on function public.wallet_credit(numeric,text,text,text,text) from public, anon;
revoke execute on function public.wallet_debit(numeric,text,text,text,text) from public, anon;
revoke execute on function public.assign_order_driver(text,text) from public, anon;
revoke execute on function public.create_order(jsonb,text,text,double precision,double precision) from public, anon;

grant execute on function public.redeem_merchant_invite(text) to authenticated;
grant execute on function public.transition_order(text,text,text) to authenticated;
grant execute on function public.wallet_credit(numeric,text,text,text,text) to authenticated;
grant execute on function public.wallet_debit(numeric,text,text,text,text) to authenticated;
grant execute on function public.assign_order_driver(text,text) to authenticated;
grant execute on function public.create_order(jsonb,text,text,double precision,double precision) to authenticated;
