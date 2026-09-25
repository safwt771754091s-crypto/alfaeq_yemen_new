create extension if not exists pgroonga;

create index if not exists products_name_pgroonga_idx
  on public.products using pgroonga (name);
create index if not exists products_description_pgroonga_idx
  on public.products using pgroonga (description);
create index if not exists stores_name_pgroonga_idx
  on public.stores using pgroonga (name);
