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

لا توجد Cloud Functions أو Firestore في هذا المسار.
