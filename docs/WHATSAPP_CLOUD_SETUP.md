# WhatsApp Business Cloud API — Alfaeq Yemen

## البنية الإنتاجية

WhatsApp لا يعتمد على Firebase. أحداث الاستيراد والتشغيل تحفظ في Supabase، ويمكن تمريرها إلى n8n أو Edge Functions حسب مسار التشغيل.

الجداول ذات الصلة تشمل:
- `whatsapp_connections`
- `whatsapp_messages`
- `whatsapp_product_imports`
- `automation_events`

## الأسرار

أسرار Meta يجب أن تحفظ في Supabase Edge Function Secrets أو مزود الأسرار المخصص للخدمة، ولا توضع في Flutter أو GitHub أو جداول عامة.

## مسار التشغيل

1. ربط رقم WhatsApp بالمتجر من مركز الإدارة.
2. استقبال الحدث عبر endpoint الموثوق.
3. التحقق من توقيع Meta.
4. حفظ الرسالة/الاستيراد في Supabase.
5. إنشاء حدث `whatsapp.product_import.created` عند الحاجة.
6. معالجة الحدث عبر `automation-worker` أو n8n.
7. لا يتم نشر المنتج تلقائياً إلا وفق صلاحيات وقواعد المنصة.

## المسار المُنفَّذ داخل المنصة (بدون n8n)

- Edge Function: `whatsapp-webhook` — استقبال رسائل واتساب، التحقق من التوقيع، تحليل المنتج بالذكاء الاصطناعي، النشر التلقائي أو الحجز للمراجعة، والرد على التاجر.
- الجدول `whatsapp_notifications` — صندوق صادر دائم للرسائل والفواتير مع إعادة المحاولة.
- الدوال:
  - `whatsapp_ingest_message` — إدخال رسالة واردة وفتح سجل استيراد.
  - `whatsapp_set_import_parsed` — تخزين نتيجة التحليل الذكي.
  - `confirm_whatsapp_import` — اعتماد الاستيراد وتحويله إلى منتج (نشر أو مسودة).
  - `get_order_invoice` — بناء نص الفاتورة (مصدر واحد للواجهة وواتساب).
  - `whatsapp_notify_order` — إرسال الفاتورة للتاجر والسائق (والعميل اختياريًا).
  - `whatsapp_dispatch` — إرسال الرسائل المعلّقة عبر واجهة Meta.
  - `set_whatsapp_connection` / `list_whatsapp_connections` / `list_whatsapp_imports` — لوحة تحكم الأتمتة.
- الأتمتة التلقائية:
  - عند إنشاء طلب: تُجهَّز فاتورة التاجر تلقائيًا.
  - عند إسناد سائق: تُرسل نسخة إلى السائق.
  - مهمة `pg_cron` باسم `alfaeq-whatsapp-dispatch` تفرّغ الصندوق كل دقيقة (تتوقف تلقائيًا إذا لم تُضبط الأسرار).

## الأسرار (Vault)

تُخزَّن في Supabase Vault ولا تصل إلى تطبيق Flutter:

- `WHATSAPP_ACCESS_TOKEN`
- `WHATSAPP_PHONE_NUMBER_ID`
- `WHATSAPP_VERIFY_TOKEN`
- `WHATSAPP_APP_SECRET`

يمكن ضبطها من واجهة SQL عبر `select public.set_whatsapp_config(...)`، أو من مزود الأسرار. لا توجد Cloud Functions أو Firestore في هذا المسار.

## خطوات التشغيل عند المالك

1. إنشاء تطبيق Meta WhatsApp Business والحصول على التوكن ورقم المرسل.
2. ضبط الأسرار الأربعة أعلاه.
3. تعيين Webhook URL إلى: `https://<project-ref>.supabase.co/functions/v1/whatsapp-webhook`
4. استخدام رمز التحقق `WHATSAPP_VERIFY_TOKEN` في إعدادات Meta.
