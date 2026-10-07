-- تصحيح المبالغة في أسعار كتالوج سوبر الفائق (كانت 3.75 ضعف السعر الحقيقي).
--
-- هجرة 20261005300000_catalog_currency_correction_v1 ضربت أسعار الكتالوج
-- المستوردة في 3.75 بحجّة أنها كانت بالدولار، لكن قيم ملف المصدر كانت أصلاً
-- بالريال السعودي، فنتجت أسعار أعلى 3.75 مرة (مثال: «سكر سعودي ناعم 1 كجم»
-- 14.21 ر.س بدل 3.79 ر.س). هنا نعكس المبالغة مرة واحدة فقط، مع علامة تمنع
-- إعادة التطبيق.

update public.products
set price = round(price / coalesce((public.get_fx_rates() -> 'rates' ->> 'SAR')::numeric, 3.75), 2),
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'price_overcorrection_fixed', true,
      'price_overcorrection_fixed_at', now()
    ),
    updated_at = now()
where coalesce((metadata ->> 'price_currency_corrected')::boolean, false) = true
  and coalesce((metadata ->> 'price_overcorrection_fixed')::boolean, false) = false;
