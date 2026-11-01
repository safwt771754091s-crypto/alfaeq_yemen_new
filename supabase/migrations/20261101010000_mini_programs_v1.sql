-- Mini Programs platform (منصة البرامج المصغّرة) — a WeChat-style 小程序 registry.
--
-- Turns the launcher from a hard-coded list into a real platform: each mini
-- program is a registered row with its own identity, category, entry route and
-- publisher, so third parties (and staff) can publish new mini apps without a
-- client release. Additive only: a new table, RLS, a touch trigger and one
-- read RPC. No existing object is altered.

create table if not exists public.mini_programs (
  id text primary key,
  slug text not null unique,
  name text not null,
  description text not null default '',
  icon text not null default 'explore',
  route text not null,
  category text not null default 'عام',
  publisher_id uuid references auth.users(id) on delete set null,
  publisher_name text,
  verified boolean not null default false,
  featured boolean not null default false,
  status text not null default 'active' check (status in ('active', 'hidden')),
  sort_order integer not null default 100,
  usage_count integer not null default 0 check (usage_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists mini_programs_status_idx on public.mini_programs (status, sort_order);
create index if not exists mini_programs_category_idx on public.mini_programs (category);

alter table public.mini_programs enable row level security;

-- Everyone signed in can browse the catalog; only platform staff may change it.
drop policy if exists mini_programs_read on public.mini_programs;
create policy mini_programs_read on public.mini_programs for select to authenticated
  using (status = 'active' or publisher_id = auth.uid() or private.is_platform_staff());

drop policy if exists mini_programs_insert on public.mini_programs;
create policy mini_programs_insert on public.mini_programs for insert to authenticated
  with check (private.is_platform_staff());

drop policy if exists mini_programs_update on public.mini_programs;
create policy mini_programs_update on public.mini_programs for update to authenticated
  using (private.is_platform_staff())
  with check (private.is_platform_staff());

drop policy if exists mini_programs_delete on public.mini_programs;
create policy mini_programs_delete on public.mini_programs for delete to authenticated
  using (private.is_platform_staff());

revoke all on public.mini_programs from public, anon;
grant select, insert, update, delete on public.mini_programs to authenticated;
grant all on public.mini_programs to service_role;

create or replace function private.mini_program_touch_updated_at()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists mini_programs_touch on public.mini_programs;
create trigger mini_programs_touch before update on public.mini_programs
  for each row execute function private.mini_program_touch_updated_at();

-- The launcher reads the whole catalog through one RPC so it can page/refresh
-- without exposing the table's write surface.
create or replace function public.mini_programs_list(p_limit integer default 200)
returns table (
  id text, slug text, name text, description text, icon text, route text,
  category text, publisher_name text, verified boolean, featured boolean,
  usage_count integer, sort_order integer
)
language sql stable security definer set search_path = public, pg_temp as $$
  select m.id, m.slug, m.name, m.description, m.icon, m.route,
         m.category, m.publisher_name, m.verified, m.featured,
         m.usage_count, m.sort_order
  from public.mini_programs m
  where m.status = 'active' or m.publisher_id = auth.uid() or private.is_platform_staff()
  order by m.featured desc, m.sort_order asc, m.name asc
  limit greatest(1, least(coalesce(p_limit, 200), 500));
$$;

revoke all on function public.mini_programs_list(integer) from public, anon;
grant execute on function public.mini_programs_list(integer) to authenticated, service_role;

-- Records a launch so the catalog can rank by real popularity. Best-effort and
-- bounded; it never fails the caller.
create or replace function public.mini_program_register_use(p_id text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.mini_programs
     set usage_count = least(usage_count + 1, 2147483647)
   where id = p_id and status = 'active';
end $$;

revoke all on function public.mini_program_register_use(text) from public, anon;
grant execute on function public.mini_program_register_use(text) to authenticated, service_role;

-- Seed the first-party mini programs. `route` is resolved by the client to a
-- concrete screen; ids are stable so re-running is idempotent.
insert into public.mini_programs (id, slug, name, description, icon, route, category, verified, featured, sort_order) values
  ('mp-markets',       'markets',       'المتاجر والبقالات', 'شراء من المتاجر والسوبرماركت والبقالات', 'storefront',       'section:markets',       'تسوّق',   true, true,  10),
  ('mp-restaurants',   'restaurants',   'المطاعم',          'طلبات الطعام الجاهزة من المطاعم',       'restaurant',       'section:restaurants',   'طعام',    true, true,  20),
  ('mp-pharmacies',    'pharmacies',    'الصيدليات',        'منتجات وخدمات الصيدليات',               'pharmacy',         'section:pharmacies',    'صحة',     true, false, 30),
  ('mp-beauty',        'beauty',        'التجميل والعناية', 'العناية والجمال',                       'beauty',           'section:beauty',        'تسوّق',   true, false, 40),
  ('mp-construction',  'construction',  'مواد البناء',      'مواد ومركبات النقل الثقيل',             'construction',     'section:construction',  'خدمات',   true, false, 50),
  ('mp-cars',          'cars',          'السيارات',         'بيع وتأجير وصيانة',                     'car',              'section:cars',          'خدمات',   true, false, 60),
  ('mp-travel',        'travel',        'السفر والطيران',   'حجوزات السفر والرحلات',                 'flight',           'section:travel',        'سفر',     true, false, 70),
  ('mp-hotels',        'hotels',        'الفنادق',          'حجوزات الفنادق والشقق',                 'hotel',            'section:hotels',        'سفر',     true, false, 80),
  ('mp-banks',         'banks',         'البنوك والمحافظ',  'خدمات مالية ومحافظ إلكترونية',          'account_balance',  'section:banks',         'مالية',   true, false, 90),
  ('mp-services',      'services',      'الخدمات والحرف',   'مهنيون وخدمات منزلية',                  'handyman',         'section:services',      'خدمات',   true, false, 100),
  ('mp-electronics',   'electronics',   'الإلكترونيات',     'أجهزة وملحقات',                         'devices',          'section:electronics',   'تسوّق',   true, false, 110),
  ('mp-real-estate',   'real-estate',   'العقارات',         'بيع وإيجار العقارات',                   'home',             'section:real_estate',   'عقار',    true, false, 120),
  ('mp-jobs',          'jobs',          'الوظائف',          'فرص العمل والتوظيف',                    'work',             'section:jobs',          'أعمال',   true, false, 130),
  ('mp-education',     'education',     'التعليم والتدريب', 'دورات ومدربون ومراكز',                  'school',           'section:education',     'تعليم',   true, false, 140),
  ('mp-health',        'health',        'الصحة والعيادات',  'عيادات ومواعيد وخدمات صحية',            'medical',          'section:health',        'صحة',     true, false, 150),
  ('mp-tourism',       'tourism',       'السياحة والرحلات', 'رحلات وتجارب داخل اليمن',               'explore',          'section:local_tourism', 'سفر',     true, false, 160),
  ('mp-reels',         'reels',         'فيديو الفائق',     'مقاطع قصيرة وبث مباشر',                 'play',             'screen:reels',          'ترفيه',   true, true,  5),
  ('mp-moments',       'moments',       'اللحظات',          'شارك أخبارك وعروضك',                    'photo',            'screen:moments',        'اجتماعي', true, false, 170),
  ('mp-live',          'live',          'البث المباشر',     'غرف بث مباشر مع دردشة حيّة',            'live',             'screen:live',           'ترفيه',   true, false, 175),
  ('mp-wallet',        'wallet',        'محفظة الفائق',     'محفظتك الإلكترونية والحوالات',          'account_balance_wallet', 'screen:wallet',  'مالية',   true, true,  15),
  ('mp-ai',            'ai',            'ذكاء الفائق',      'مساعدك الذكي للبحث والطلب',             'auto_awesome',     'screen:ai',             'أدوات',   true, true,  8),
  ('mp-contact',       'contact',       'تواصل معنا',       'الدعم والتواصل الرسمي',                 'support_agent',    'screen:contact',        'دعم',     true, false, 180)
on conflict (id) do update set
  slug = excluded.slug,
  name = excluded.name,
  description = excluded.description,
  icon = excluded.icon,
  route = excluded.route,
  category = excluded.category,
  verified = excluded.verified,
  featured = excluded.featured,
  sort_order = excluded.sort_order;
