-- FIX: public.ensure_my_wallet (SECURITY INVOKER) delegates to
-- private.ensure_my_wallet_impl (SECURITY DEFINER), but the private function was
-- never granted to `authenticated` -- unlike its siblings
-- (wallet_credit_internal, transition_order_internal, ...). Every call therefore
-- failed with "permission denied for function ensure_my_wallet_impl", so no user
-- could create/load their wallet from the app (wallet center and QR page broke).

grant usage on schema private to authenticated;
grant execute on function private.ensure_my_wallet_impl(text, text) to authenticated;
