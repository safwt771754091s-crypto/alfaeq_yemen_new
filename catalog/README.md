# كتالوج الفائق يمن (معرض عام)

معرض عام لكل منتجات المتجر يظهر للجميع، مع تمييز واضح للأصناف التي **ينقصها صورة**.

## الروابط
- المعرض المنشور: `https://safwt771754091s-crypto.github.io/alfaeq_yemen_new/catalog/`
- داخل التطبيق: صفحة «تعديل المنتج» تتيح للمالك/التاجر رفع صورة مباشرة إلى Supabase Storage.

## الملفات
- `index.html` — المعرض (بحث بالاسم/المعرّف + تصفية: الكل / ينقصها صورة / بصور).
- `products.json` — لقط كامل للكتالوج (id, name, price, currency, image, store_id, section_id).
- `missing-images.json` — المنتجات التي تحتاج صورة فقط.

## التحديث
يُعاد توليد الملفات تلقائياً:
- عند النشر على `main` (ضمن `flutter_build.yml` — يُنسخ المعرض إلى موقع Pages).
- يومياً عبر `product-gallery.yml` ثم يُحفظ التغيير في المستودع.

يدوياً:

```bash
python3 tools/build_product_gallery.py --out catalog
```

المصدر هو جدول `products` في Supabase (قراءة فقط بمفتاح publishable).
لرفع الصور: صفحة تعديل المنتج في التطبيق (تحدّث `products.image_url` إلى رابط عام في bucket `media`).
