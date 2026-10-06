-- Realtime publication parity for tables the app subscribes to with
-- `.stream()`. login_events was missing, which made the admin dashboard's
-- login log show "تعذر قراءة سجل الدخول"; products/stores were also missing
-- so their live lists never refreshed. Idempotent and additive.
do $$
declare
  t text;
begin
  foreach t in array array['login_events', 'products', 'stores'] loop
    if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = t)
       and not exists (
         select 1 from pg_publication_tables
         where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
       ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
