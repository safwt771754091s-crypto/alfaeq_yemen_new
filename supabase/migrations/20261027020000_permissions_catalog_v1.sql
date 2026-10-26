-- Full platform permission catalog.
--
-- Before this migration the master permission model only knew the ten
-- permissions seeded by 20261025040000_master_bank_deposits_v1.sql, so the
-- owner could not grant or revoke anything else. This migration records every
-- platform permission in a readable catalog and grants the whole set to every
-- owner/admin account.
--
-- Idempotent: safe to re-run. Existing grants are preserved.

create table if not exists public.permissions_catalog (
  permission text primary key,
  label_ar text not null,
  category text not null,
  sort_order int not null default 100
);

alter table public.permissions_catalog enable row level security;

drop policy if exists permissions_catalog_read on public.permissions_catalog;
create policy permissions_catalog_read on public.permissions_catalog
  for select to authenticated using (true);

grant select on public.permissions_catalog to authenticated;

insert into public.permissions_catalog (permission, label_ar, category, sort_order) values
  ('admin.dashboard',                 'لوحة الإدارة',                     'admin',      10),
  ('admin.users.manage',              'إدارة الحسابات والصلاحيات',        'admin',      20),
  ('admin.merchants.approve',         'اعتماد التجار',                    'admin',      30),
  ('admin.payouts.review',            'مراجعة المستحقات والمدفوعات',      'admin',      40),
  ('wallet.deposits.review',          'مراجعة إيداعات المحفظة',           'wallet',     50),
  ('wallet.deposits.reject',          'رفض إيداعات المحفظة',              'wallet',     60),
  ('wallet.withdraw.review',          'مراجعة طلبات السحب',               'wallet',     70),
  ('wallet.adjust',                   'تعديل أرصدة المحافظ',              'wallet',     80),
  ('wallet.vouchers.manage',          'إدارة رموز شحن المحفظة',           'wallet',     90),
  ('products.manage',                 'إدارة الأصناف',                    'catalog',   100),
  ('products.bulk_import',            'استيراد الأصناف من Excel',         'catalog',   110),
  ('products.review',                 'مراجعة واعتماد الأصناف',           'catalog',   120),
  ('sections.manage',                 'إدارة الأقسام',                    'catalog',   130),
  ('merchants.manage',                'إدارة التجار والمتاجر',            'merchants', 140),
  ('merchants.approve',               'اعتماد المتاجر',                   'merchants', 150),
  ('merchants.invites',               'دعوات التجار والروابط',            'merchants', 160),
  ('orders.manage',                   'إدارة الطلبات',                    'orders',    170),
  ('orders.dispatch',                 'التوزيع وإسناد الطلبات',           'orders',    180),
  ('orders.refund',                   'الاسترجاع وإلغاء الطلبات',         'orders',    190),
  ('payments.review',                 'مراجعة الحوالات والدفع',           'orders',    200),
  ('drivers.manage',                  'إدارة المندوبين',                  'drivers',   210),
  ('drivers.approve',                 'اعتماد طلبات المندوبين',           'drivers',   220),
  ('delivery.zones.manage',           'مناطق وأسعار التوصيل',             'drivers',   230),
  ('content.reels',                   'إدارة الفيديو القصير',             'content',   240),
  ('content.live',                    'إدارة غرف البث المباشر',           'content',   250),
  ('content.updates',                 'تحديثات الصفحة الرئيسية',          'content',   260),
  ('automation.manage',               'أتمتة المنصة',                     'automation',270),
  ('whatsapp.automation',             'أتمتة واتساب',                     'automation',280),
  ('ai.assistant',                    'مساعد ذكاء الفائق',                'ai',        290),
  ('ai.operations',                   'تشغيل مهام الذكاء الاصطناعي',      'ai',        300),
  ('platform.settings',               'إعدادات المنصة',                   'platform',  310),
  ('platform.bank_accounts.manage',   'إدارة الحسابات البنكية',           'platform',  320),
  ('platform.fx_rates',               'أسعار الصرف',                      'platform',  330),
  ('platform.mini_programs',          'البرامج المصغرة',                  'platform',  340),
  ('developer.center',                'مركز المطور',                      'developer', 350),
  ('developer.security_audit',        'الفحص الأمني والتدقيق',            'developer', 360)
on conflict (permission) do update
  set label_ar = excluded.label_ar,
      category = excluded.category,
      sort_order = excluded.sort_order;

-- Grant the complete catalog to every existing owner/admin account. Existing
-- rows (and any explicit revocations) are left untouched.
insert into public.master_permissions (uid, permission, granted, note)
select u.uid, c.permission, true, 'منح تلقائي لحساب المالك'
from public.users u
cross join public.permissions_catalog c
where coalesce(u.owner, false)
   or coalesce(u.admin, false)
   or u.role in ('owner', 'admin')
on conflict (uid, permission) do nothing;

-- New owner accounts created later inherit the full catalog automatically.
create or replace function private.grant_all_permissions_to_owner()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
begin
  if coalesce(new.owner, false) or coalesce(new.admin, false) or new.role in ('owner', 'admin') then
    insert into public.master_permissions (uid, permission, granted, note)
    select new.uid, c.permission, true, 'منح تلقائي لحساب المالك'
    from public.permissions_catalog c
    on conflict (uid, permission) do nothing;
  end if;
  return new;
end $$;

drop trigger if exists grant_all_permissions_on_owner on public.users;
create trigger grant_all_permissions_on_owner
  after insert or update of owner, admin, role on public.users
  for each row execute function private.grant_all_permissions_to_owner();
