# Alfaeq Automation Platform v1

هذه المرحلة تنفذ طبقة **Google Sheets → n8n → Supabase** ضمن مسار الأتمتة الإنتاجي.

## القاعدة المعمارية

- **Google Sheets:** واجهة تحرير واستيراد جماعي سهلة للمنتجات وملفات العملاء وقائمة الأقسام.
- **n8n:** التنسيق والتحقق والنقل بين الأنظمة.
- **Supabase:** المصدر التشغيلي الرسمي للبيانات.
- **Inventory:** لا يتم تعديل المخزون من Sheet catalog sync؛ تغييرات المخزون يجب أن تمر عبر مسار المخزون/ledger حتى لا تتعارض مع الطلبات.

## الملفات

- `n8n/alfaeq_google_sheets_sync.json` — Workflow قابل للاستيراد إلى n8n.
- `supabase/functions/sheets-catalog-sync/index.ts` — Edge Function تستقبل الصفوف وتتحقق منها وتحدّث المنتجات أو ملفات العملاء.
- `supabase/migrations/20260928010000_google_sheets_import_audit_v1.sql` — سجل عمليات الاستيراد.

## متغيرات n8n

- `ALFAEQ_SHEETS_SYNC_URL` = `https://<project-ref>.supabase.co/functions/v1/sheets-catalog-sync`
- `ALFAEQ_SHEETS_SYNC_SECRET` = نفس السر المحفوظ في Supabase Secret باسم `ALFAEQ_SHEETS_SYNC_SECRET`.

لا تُحفظ الأسرار في GitHub أو داخل Flutter.

## البيانات

### Products
الحد الأدنى: `reference, name, store_id, section_id, price`
اختياري: `description, image_url, currency, sale_unit, status`

### Customers
التعديل يتم على المستخدمين الموجودين فقط باستخدام `uid, name, metadata`.
لا يتم إنشاء حسابات Supabase Auth من Google Sheets، ولا يتم تعديل كلمات المرور أو الأدوار أو الأرصدة أو السجلات المالية.

### Categories / Sections
استخدم IDs الموجودة في التطبيق:
`markets, restaurants, pharmacies, beauty, construction, cars, travel, hotels, banks, services, electronics, real_estate, jobs, education, health, local_tourism`

## التشغيل

1. نشر Edge Function.
2. ضبط Secret في Supabase.
3. استيراد Workflow إلى n8n.
4. ضبط متغيري n8n.
5. ربط Google Sheets Node لإرسال الصفوف إلى Webhook.
6. أول تشغيل يكون `dry_run=true`.
7. بعد مراجعة النتيجة، تشغيل `dry_run=false`.
