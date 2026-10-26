-- Fix corrupted pgroonga search indexes.
--
-- Symptom observed in production: the owner's product list and the admin
-- dashboard showed a wrong total (and the public catalog looked truncated)
-- even though the table held thousands of rows. Root cause: the pgroonga
-- indexes on products.name / products.description / stores.name went stale
-- (bulk catalog imports landed rows the index never saw), so the planner
-- satisfied `count(*)` and `order by name` straight from the index and only
-- returned the handful of rows the index knew about.
--
-- `count(*)` returned 195 while `count(id)` (a real heap scan) returned 3906.
-- Rebuilding the indexes restores the planner's view of the table.
--
-- This migration is idempotent: it only rebuilds indexes that already exist.

do $$
declare
  idx text;
begin
  foreach idx in array array[
    'public.products_name_pgroonga_idx',
    'public.products_description_pgroonga_idx',
    'public.stores_name_pgroonga_idx'
  ] loop
    if exists (
      select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = split_part(idx, '.', 1)
        and c.relname = split_part(idx, '.', 2)
    ) then
      execute format('reindex index %s', idx);
    end if;
  end loop;
end $$;

-- Refresh planner statistics so the fixed indexes are actually chosen.
analyze public.products;
analyze public.stores;
