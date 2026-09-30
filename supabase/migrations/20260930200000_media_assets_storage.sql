-- Production media registry and Supabase Storage bucket.
create table if not exists public.media_assets (
  id uuid primary key default gen_random_uuid(),
  owner_id text not null references public.users(uid) on delete cascade,
  entity_type text null,
  entity_id text null,
  source text not null default 'supabase_storage'
    check (source in ('supabase_storage','google_photos','external_url')),
  source_id text null,
  bucket text null,
  object_path text null,
  public_url text null,
  mime_type text null,
  width integer null check (width is null or width > 0),
  height integer null check (height is null or height > 0),
  is_public boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists media_assets_entity_idx on public.media_assets(entity_type, entity_id, created_at desc);
create index if not exists media_assets_owner_idx on public.media_assets(owner_id, created_at desc);
create unique index if not exists media_assets_source_unique_idx on public.media_assets(source, source_id) where source_id is not null;
alter table public.media_assets enable row level security;
drop policy if exists media_assets_select on public.media_assets;
create policy media_assets_select on public.media_assets for select to anon, authenticated using (is_public or owner_id = (select auth.uid())::text);
drop policy if exists media_assets_insert on public.media_assets;
create policy media_assets_insert on public.media_assets for insert to authenticated with check (owner_id = (select auth.uid())::text);
drop policy if exists media_assets_update on public.media_assets;
create policy media_assets_update on public.media_assets for update to authenticated using (owner_id = (select auth.uid())::text) with check (owner_id = (select auth.uid())::text);
drop policy if exists media_assets_delete on public.media_assets;
create policy media_assets_delete on public.media_assets for delete to authenticated using (owner_id = (select auth.uid())::text);
insert into storage.buckets (id, name, public) values ('media', 'media', true) on conflict (id) do update set public = excluded.public;
drop policy if exists media_public_read on storage.objects;
create policy media_public_read on storage.objects for select to anon, authenticated using (bucket_id = 'media');
drop policy if exists media_owner_insert on storage.objects;
create policy media_owner_insert on storage.objects for insert to authenticated with check (bucket_id = 'media' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists media_owner_update on storage.objects;
create policy media_owner_update on storage.objects for update to authenticated using (bucket_id = 'media' and (storage.foldername(name))[1] = (select auth.uid())::text) with check (bucket_id = 'media' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists media_owner_delete on storage.objects;
create policy media_owner_delete on storage.objects for delete to authenticated using (bucket_id = 'media' and (storage.foldername(name))[1] = (select auth.uid())::text);
