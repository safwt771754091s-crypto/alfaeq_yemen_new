-- Restore EXECUTE on two private RPC internals that invoker wrappers call.
--
-- public.create_order and public.ensure_driver_profile are SECURITY INVOKER
-- wrappers that delegate to private.* implementations. The hardening pass
-- revoked EXECUTE on the private internals but only re-granted four of them
-- (20260925020100), so these two wrappers fail at runtime with
-- 42501 "permission denied for function ...".
--
-- The internals are SECURITY DEFINER and each re-checks auth.uid() and the
-- caller's JWT role, so granting EXECUTE to authenticated adds no privilege:
--   * create_order_internal attributes the order to auth.uid()
--   * ensure_driver_profile requires a driver/admin JWT role

grant execute on function private.create_order_internal(jsonb, text, text, double precision, double precision) to authenticated;
grant execute on function private.ensure_driver_profile() to authenticated;
