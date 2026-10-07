-- فصل قسم المطاعم عن البقالات/السوبرماركت.
-- المتجر الوحيد الحالي (سوبر الفائق) هو بقالة/سوبرماركت، لذا تُنقل أصنافه
-- من قسم "المطاعم والبقالات" إلى قسم "المتاجر والأسواق"، ويُخصّص قسم
-- "المطاعم" لطلبات الطعام الجاهزة فقط. لا حذف بيانات؛ تحديث وصفي فقط.

update public.sections
set title = 'المطاعم',
    subtitle = 'طلبات الطعام الجاهزة من المطاعم',
    updated_at = now()
where id = 'restaurants';

-- الأصناف التي كانت موسومة خطأً بقسم المطاعم (كلها من متجر بقالة) تعود للمتاجر.
update public.products
set section_id = 'markets',
    updated_at = now()
where section_id = 'restaurants'
  and store_id in (select id from public.stores where section_id = 'markets');
