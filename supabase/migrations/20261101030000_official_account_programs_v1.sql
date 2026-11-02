-- Official Accounts ⇄ Mini Programs (ربط الحسابات الرسمية بالبرامج المصغّرة) —
-- the WeChat 公众号 ↔ 小程序 link: every official account can publish and own
-- mini programs that then surface both on its profile and in the global
-- catalog. Built-in programs stay staff-managed; account-bound programs are
-- managed by their account owner. Additive only: one column, one index, three
-- owner policies and one read RPC.

alter table public.mini_programs
  add column if not exists account_id uuid references public.official_accounts(id) on delete set null;

create index if not exists mini_programs_account_idx on public.mini_programs (account_id);

-- Owners may manage the programs bound to their own accounts. The existing
-- staff policies (mini_programs_insert/update/delete) remain; permissive
-- policies are OR-ed, so these only widen write access to account owners.
drop policy if exists mini_programs_owner_insert on public.mini_programs;
create policy mini_programs_owner_insert on public.mini_programs for insert to authenticated
  with check (
    account_id is not null
    and exists (select 1 from public.official_accounts a where a.id = account_id and a.owner_id = auth.uid())
  );

drop policy if exists mini_programs_owner_update on public.mini_programs;
create policy mini_programs_owner_update on public.mini_programs for update to authenticated
  using (
    account_id is not null
    and exists (select 1 from public.official_accounts a where a.id = account_id and a.owner_id = auth.uid())
  )
  with check (
    account_id is not null
    and exists (select 1 from public.official_accounts a where a.id = account_id and a.owner_id = auth.uid())
  );

drop policy if exists mini_programs_owner_delete on public.mini_programs;
create policy mini_programs_owner_delete on public.mini_programs for delete to authenticated
  using (
    account_id is not null
    and exists (select 1 from public.official_accounts a where a.id = account_id and a.owner_id = auth.uid())
  );

-- Programs bound to one account. Owners (and staff) see hidden ones too;
-- everyone else only sees active ones, matching the catalog's visibility rule.
create or replace function public.account_mini_programs(p_account_id uuid)
returns table (
  id text, slug text, name text, description text, icon text, route text,
  category text, account_id uuid, verified boolean, status text,
  usage_count integer, sort_order integer, created_at timestamptz
)
language sql stable security definer set search_path = public, pg_temp as $$
  select m.id, m.slug, m.name, m.description, m.icon, m.route, m.category,
         m.account_id, m.verified, m.status, m.usage_count, m.sort_order, m.created_at
  from public.mini_programs m
  join public.official_accounts a on a.id = m.account_id
  where m.account_id = p_account_id
    and (m.status = 'active' or a.owner_id = auth.uid() or private.is_platform_staff())
  order by m.sort_order asc, m.created_at asc;
$$;

revoke all on function public.account_mini_programs(uuid) from public, anon;
grant execute on function public.account_mini_programs(uuid) to authenticated, service_role;
