# Alfaeq Master Automation — Event Engine v2

هذه المرحلة تبني **بوابة أحداث موحدة** للفائق يمن.

## المسار

Flutter/Supabase → **Alfaeq Event Webhook** → Validate & Normalize → **Supabase Event Inbox (idempotency)** → Route Event → automation handlers → Respond.

### قواعد v2

- كل حدث يجب أن يحمل: `eventId`, `eventType`, `occurredAt`.
- `eventId` فريد؛ إعادة إرسال الحدث نفسه لا تنشئ نسخة ثانية في الـ inbox.
- Supabase هو سجل الاستقبال التشغيلي للأحداث.
- n8n ينسق الأتمتة ولا يصبح مصدر الحقيقة للطلبات أو المخزون.
- مخزون المنتجات لا يتغير من مسار الكتالوج أو event router مباشرة؛ تغيير المخزون يمر عبر inventory/ledger.
- الأسرار لا تدخل Flutter أو GitHub؛ تستخدم متغيرات n8n/credentials.

## متغيرات n8n المطلوبة

- `ALFAEQ_N8N_SHARED_SECRET`
- `ALFAEQ_SUPABASE_REST_URL` — مثال: `https://<project-ref>.supabase.co/rest/v1/automation_event_inbox`
- `ALFAEQ_SUPABASE_SERVICE_ROLE_KEY` — يحفظ داخل n8n فقط.
- `ALFAEQ_IMAGE_STUDIO_URL` و `ALFAEQ_IMAGE_STUDIO_TOKEN` عند تفعيل مسار الصور.
- `ALFAEQ_WHATSAPP_AUTOMATION_URL` عند تفعيل مسار واتساب.

## عقد الحدث

```json
{
  "source": "alfaeq_yemen_new",
  "version": 1,
  "eventId": "uuid-or-stable-id",
  "eventType": "order.created",
  "occurredAt": "2026-09-28T12:00:00Z",
  "data": {}
}
```

## الاختبار

أرسل POST إلى Webhook مع header `x-alfaeq-automation-secret`.
ابدأ بـ `test.ping`. يجب أن يصل إلى Event Inbox ثم يعود رد JSON يحتوي `accepted: true`.
إعادة إرسال نفس `eventId` يجب أن تكون `duplicate: true` ولا تضيف صفاً جديداً.
