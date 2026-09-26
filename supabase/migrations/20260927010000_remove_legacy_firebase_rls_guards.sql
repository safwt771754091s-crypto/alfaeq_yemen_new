-- Supabase is now the sole application identity/backend path.
-- The former Firebase-project JWT guard policies are obsolete and must not
-- remain as an authorization dependency.
do $$
declare r record;
begin
  for r in
    select tablename, policyname
    from pg_policies
    where schemaname='public' and policyname like 'firebase_project_guard_%'
  loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;
