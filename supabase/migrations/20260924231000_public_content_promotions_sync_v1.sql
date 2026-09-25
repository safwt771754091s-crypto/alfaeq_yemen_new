create table if not exists public.promotions (
  id text primary key,
  product_id text null references public.products(id) on delete set null,
  store_id text null references public.stores(id) on delete set null,
  title text not null,
  description text null,
  discount_percent numeric(5,2) null check (discount_percent is null or (discount_percent >= 0 and discount_percent <= 100)),
  price numeric(14,2) null check (price is null or price >= 0),
  original_price numeric(14,2) null check (original_price is null or original_price >= 0),
  image_url text null,
  banner_url text null,
  status text not null default 'draft' check (status in ('draft','scheduled','published','paused','expired')),
  starts_at timestamptz not null default now(),
  ends_at timestamptz null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.public_site_updates (
  id text primary key,
  title text not null,
  summary text null,
  body text null,
  image_url text null,
  cta_label text null,
  cta_url text null,
  status text not null default 'draft' check (status in ('draft','published','archived')),
  published_at timestamptz null,
  expires_at timestamptz null,
  sort_order integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.promotions enable row level security;
alter table public.public_site_updates enable row level security;

drop policy if exists promotions_public_read on public.promotions;
create policy promotions_public_read on public.promotions for select to anon, authenticated
using (status = 'published' and starts_at <= now() and (ends_at is null or ends_at > now()));

drop policy if exists site_updates_public_read on public.public_site_updates;
create policy site_updates_public_read on public.public_site_updates for select to anon, authenticated
using (status = 'published' and (published_at is null or published_at <= now()) and (expires_at is null or expires_at > now()));

create index if not exists promotions_public_window_idx on public.promotions (status, starts_at, ends_at, updated_at desc);
create index if not exists promotions_product_idx on public.promotions (product_id, status);
create index if not exists site_updates_public_idx on public.public_site_updates (status, published_at desc, sort_order, updated_at desc);

create or replace function public.enqueue_content_automation()
returns trigger language plpgsql security definer set search_path = public as $$
declare aggregate_id text; event_type text; aggregate_type text;
begin
  aggregate_id := coalesce(new.id, old.id);
  aggregate_type := case when tg_table_name = 'promotions' then 'promotion' else 'site_update' end;
  event_type := case when tg_op = 'INSERT' then aggregate_type || '.created' when tg_op = 'UPDATE' then aggregate_type || '.updated' else aggregate_type || '.deleted' end;
  insert into public.automation_events(event_type, aggregate_type, aggregate_id, payload)
  values (event_type, aggregate_type, aggregate_id, jsonb_build_object('source','supabase','table',tg_table_name,'operation',tg_op,'record',to_jsonb(new),'previous',case when tg_op='UPDATE' then to_jsonb(old) else null end));
  return coalesce(new, old);
end; $$;

drop trigger if exists promotions_automation_event on public.promotions;
create trigger promotions_automation_event after insert or update or delete on public.promotions for each row execute function public.enqueue_content_automation();

drop trigger if exists site_updates_automation_event on public.public_site_updates;
create trigger site_updates_automation_event after insert or update or delete on public.public_site_updates for each row execute function public.enqueue_content_automation();
