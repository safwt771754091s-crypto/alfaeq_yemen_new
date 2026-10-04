-- SECURITY: public.wallet_credit / public.wallet_debit are thin SECURITY INVOKER
-- wrappers over private.wallet_*_internal, which are SECURITY DEFINER and act on
-- auth.uid()'s OWN wallet. Because authenticated had EXECUTE on the public wrappers,
-- any signed-in user could call wallet_credit(1000000, ...) and mint unlimited
-- balance into their own wallet -- a critical money-minting hole (the app never
-- calls these RPCs; credits/debits must be performed server-side only).
--
-- The private schema is not exposed through PostgREST, so revoking the public
-- wrappers from client roles fully closes the path while keeping service_role
-- (server) access intact.

revoke execute on function public.wallet_credit(numeric, text, text, text, text) from public, anon, authenticated;
revoke execute on function public.wallet_debit(numeric, text, text, text, text) from public, anon, authenticated;

grant execute on function public.wallet_credit(numeric, text, text, text, text) to service_role;
grant execute on function public.wallet_debit(numeric, text, text, text, text) to service_role;
