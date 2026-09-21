# أتمتة الفائق يمن عبر n8n

هذا المجلد يضيف طبقة أتمتة خارجية قابلة للاستبدال فوق Firebase. التطبيق يبقى Flutter + Firebase، بينما n8n يتولى التنسيق بين الخدمات الخارجية.

## المسار

Flutter/Firebase → Cloud Functions → n8n Webhook → Google Sheets / WhatsApp / Image Studio

## ما تم تجهيزه

- `functions/n8n_bridge.js`: يرسل أحداث إنشاء الطلبات والمنتجات والمتاجر واستيرادات WhatsApp ودعوات التجار إلى n8n.
- `n8n/alfaeq_master_automation.json`: Workflow قابل للاستيراد في n8n.
- Google Sheets لتسجيل الأحداث.
- مسار Image Studio لطلبات صور المنتجات.
- مسار WhatsApp Automation.
- سر مشترك بين Firebase وn8n.

## الأسرار المطلوبة في Firebase Functions

```
N8N_AUTOMATION_WEBHOOK_URL
N8N_AUTOMATION_SHARED_SECRET
```

## متغيرات n8n

```
ALFAEQ_N8N_SHARED_SECRET
ALFAEQ_GOOGLE_SHEET_ID
ALFAEQ_IMAGE_STUDIO_URL
ALFAEQ_IMAGE_STUDIO_TOKEN
ALFAEQ_WHATSAPP_AUTOMATION_URL
```

ولا يوضع أي Token حقيقي داخل GitHub.

## Google Sheets

أنشئ ورقة باسم `AutomationEvents` بأعمدة:

`event_id, event_type, occurred_at, payload`

ثم اربط Credential باسم `Alfaeq Google Sheets` في n8n.

## WhatsApp

النظام الحالي في Firebase يحتوي أصلًا على تكامل WhatsApp Cloud API آمن عبر أسرار Firebase. n8n هنا طبقة تنسيق، وليس مكانًا لتخزين أسرار Meta داخل المستودع.

## Image Studio

`ALFAEQ_IMAGE_STUDIO_URL` هو endpoint للخدمة التي سيستخدمها المشروع لإنتاج/معالجة صور المنتجات. يمكن تغييره لاحقًا دون تعديل Flutter.

## ملاحظة تشغيلية

إضافة هذه الطبقة لا تعني أن WhatsApp أو Google Sheets أو Image Studio أصبحت متصلة فعليًا حتى يتم إدخال بيانات الاعتماد/عناوين الخدمات في بيئة التشغيل. الكود يرفض الأسرار الناقصة ولا يضع بيانات حساسة في GitHub.
