-- Security audit hardening (2026-11-20).
--
-- Findings from a full audit of the RLS policies, the RPC surface, and the
-- wallet/money paths. Each item is a verified privilege escalation or a broken
-- production path; nothing here changes a business rule or a client contract.
--
--   F1 CRITICAL  public.wallets INSERT was gated only on `uid`, so any signed-in
--                user could create their own wallet with an arbitrary starting
--                balance and immediately spend it (create_order_paid,
--                wallet_transfer, pay_mini_program).
--   F2 CRITICAL  private.is_platform_staff() is referenced from RLS policies on
--                products/stores/mini_programs but was revoked from `anon`, so
--                every anonymous storefront read failed with
--                "permission denied for function is_platform_staff".
--   F3 HIGH      public.product_reviews / store_reviews are granted to `anon`
--                and fall back to split_part(email,'@',1), leaking the local
--                part of customer emails on a public product page.
--   F4 MEDIUM    public.ai_agents / ai_tasks / ai_activity_log were readable by
--                every authenticated user (`using (true)`), exposing the AI
--                control plane (adapter_config, budgets, prompts, token spend).
--   F5 MEDIUM    private.wallet_credit_internal stayed granted to
--                `authenticated` after the public wrapper was revoked, leaving
--                the money primitive reachable through the private schema.
--
-- Additive and idempotent: safe to re-run. No table is dropped and no existing
-- data is rewritten. Evidence is recorded in progress.md.

-- ---------------------------------------------------------------------------
-- F1: a client-created wallet must always start empty. Only the SECURITY
-- DEFINER engines (ensure_my_wallet, wallet_credit_internal, transfer,
-- settlement, top-up vouchers) may set a balance, and they run elevated.
-- ---------------------------------------------------------------------------
drop policy if exists wallets_self_insert on public.wallets;
create policy wallets_self_insert on public.wallets
for insert to authenticated
with check (
  (select private.is_platform_staff())
  or (
    uid = public.current_user_uid()
    and coalesce(available_balance, 0) = 0
    and coalesce(version, 0) = 0
  )
);

-- ---------------------------------------------------------------------------
-- F2: the staff predicate is evaluated inside policies that also run for
-- `anon`. Granting EXECUTE does not widen access -- the function only inspects
-- the caller's own JWT/users row and every policy still gates on the result.
-- `anon` already holds USAGE on schema private (the live failure is
-- "permission denied for function", not "for schema"), so only the function
-- grant is needed here.
-- ---------------------------------------------------------------------------
grant execute on function private.is_platform_staff() to anon;

-- ---------------------------------------------------------------------------
-- F3: public review readers must never derive a display name from the email.
-- ---------------------------------------------------------------------------
create or replace function public.product_reviews(p_product_id text, p_limit int default 50)
returns jsonb
language sql
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'average', coalesce(
      (select round(avg(rating)::numeric, 2) from public.reviews where product_id = p_product_id),
      0),
    'count', (select count(*) from public.reviews where product_id = p_product_id),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
          'id', r.id,
          'rating', r.rating,
          'body', r.body,
          'user_id', r.user_id,
          'author_name', coalesce(
            nullif(u.raw_user_meta_data ->> 'full_name', ''),
            nullif(u.raw_user_meta_data ->> 'name', ''),
            'مستخدم'),
          'avatar_url', coalesce(u.raw_user_meta_data ->> 'avatar_url', ''),
          'created_at', r.created_at
        ))
      from (
        select r.* from public.reviews r
        where r.product_id = p_product_id
        order by r.created_at desc
        limit greatest(1, least(coalesce(p_limit, 50), 200))
      ) r
      left join auth.users u on u.id::text = r.user_id
    ), '[]'::jsonb)
  );
$function$;

create or replace function public.store_reviews(p_store_id text, p_limit int default 50)
returns jsonb
language sql
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'average', coalesce(
      (select round(avg(rating)::numeric, 2) from public.reviews where store_id = p_store_id),
      0),
    'count', (select count(*) from public.reviews where store_id = p_store_id),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
          'id', r.id,
          'rating', r.rating,
          'body', r.body,
          'user_id', r.user_id,
          'author_name', coalesce(
            nullif(u.raw_user_meta_data ->> 'full_name', ''),
            nullif(u.raw_user_meta_data ->> 'name', ''),
            'مستخدم'),
          'avatar_url', coalesce(u.raw_user_meta_data ->> 'avatar_url', ''),
          'created_at', r.created_at
        ))
      from (
        select r.* from public.reviews r
        where r.store_id = p_store_id
        order by r.created_at desc
        limit greatest(1, least(coalesce(p_limit, 50), 200))
      ) r
      left join auth.users u on u.id::text = r.user_id
    ), '[]'::jsonb)
  );
$function$;

revoke all on function public.product_reviews(text, int) from public;
revoke all on function public.store_reviews(text, int) from public;
grant execute on function public.product_reviews(text, int) to anon, authenticated;
grant execute on function public.store_reviews(text, int) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- F4: the AI control plane is staff-only.
-- ---------------------------------------------------------------------------
drop policy if exists "ai_agents_read_authenticated" on public.ai_agents;
drop policy if exists "ai_tasks_read_authenticated" on public.ai_tasks;
drop policy if exists "ai_activity_read_authenticated" on public.ai_activity_log;

drop policy if exists ai_agents_staff_read on public.ai_agents;
create policy ai_agents_staff_read on public.ai_agents
for select to authenticated using ((select private.is_platform_staff()));

drop policy if exists ai_tasks_staff_read on public.ai_tasks;
create policy ai_tasks_staff_read on public.ai_tasks
for select to authenticated using ((select private.is_platform_staff()));

drop policy if exists ai_activity_staff_read on public.ai_activity_log;
create policy ai_activity_staff_read on public.ai_activity_log
for select to authenticated using ((select private.is_platform_staff()));

-- ---------------------------------------------------------------------------
-- F5: credits are only issued by server-side engines. The public wrappers are
-- already service_role-only (20261004000000_revoke_self_serve_wallet_minting);
-- the private primitive must not be reachable by clients either. Its internal
-- callers are SECURITY DEFINER and do not depend on a client grant.
-- ---------------------------------------------------------------------------
revoke execute on function private.wallet_credit_internal(numeric, text, text, text, text)
  from public, anon, authenticated;
revoke execute on function private.wallet_debit_internal(numeric, text, text, text, text)
  from public, anon, authenticated;
