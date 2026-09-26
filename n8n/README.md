# أتمتة الفائق يمن عبر n8n

n8n طبقة تنسيق خارجية. **Supabase هو المصدر الخلفي الوحيد للتطبيق**.

## المسار الإنتاجي

Flutter → Supabase → `automation_events` → Supabase Edge Function `automation-worker` → n8n Webhook → الخدمات الخارجية

لا يوجد مسار Firebase/Firestore في هذا التكامل.

## نقطة الربط

Webhook الإنتاج:
`https://alffaq.app.n8n.cloud/webhook/alfaeq-events`

تُنشأ أحداث الأتمتة داخل Supabase، ثم يعالجها `automation-worker`. السر المشترك يُحفظ server-side ولا يوضع داخل Flutter أو GitHub.

## الخدمات الخارجية

يمكن لـ n8n تنسيق:
- Google Sheets لتسجيل أحداث الأتمتة.
- WhatsApp Automation.
- Image Studio لصور المنتجات.

مفاتيح الخدمات الخارجية لا تُحفظ في المستودع.

## الأحداث

النظام يدعم أحداثاً مثل:
- `order.created`
- `order.updated`
- `product.created`
- `product.updated`
- `store.created`
- `whatsapp.product_import.created`
- `merchant.invite.created`

لا نعتبر تكامل n8n متصلاً فعلياً إلا بعد ظهور تنفيذ ناجح للـwebhook ومعالجة الحدث في Supabase.
