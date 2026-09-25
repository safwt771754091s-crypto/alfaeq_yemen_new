-- Allow authenticated public RPC wrappers to invoke private, auth-checked internals.
grant usage on schema private to authenticated;
grant execute on function private.redeem_merchant_invite_internal(text) to authenticated;
grant execute on function private.transition_order_internal(text,text,text) to authenticated;
grant execute on function private.wallet_credit_internal(numeric,text,text,text,text) to authenticated;
grant execute on function private.wallet_debit_internal(numeric,text,text,text,text) to authenticated;
