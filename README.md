# الفائق يمن — منصة إنتاجية مبنية على Supabase

المستودع الرسمي لمنصة الفائق يمن. البنية الحالية تعتمد **Supabase فقط** كطبقة الخلفية: Auth وPostgreSQL وRLS وRealtime وEdge Functions وStorage عند الحاجة.

- Web وAndroid مبنيان من نفس commit.
- لا يعتمد التطبيق على Firebase أو Firestore أو Cloud Functions.
- بيانات المتاجر والمنتجات والسلة والطلبات والحسابات محفوظة في Supabase الإنتاجي.
- لا توجد بيانات تجريبية تُعامل كبيانات إنتاجية.

## روابط عامة

- 🌐 **نسخة الويب:** https://safwt771754091s-crypto.github.io/alfaeq_yemen_new/
- ⬇️ **صفحة التحميل (أندرويد):** https://safwt771754091s-crypto.github.io/alfaeq_yemen_new/store/
- 📱 **أحدث إصدار (APK + AAB):** https://github.com/safwt771754091s-crypto/alfaeq_yemen_new/releases/latest
- 🔒 **سياسة الخصوصية:** https://safwt771754091s-crypto.github.io/alfaeq_yemen_new/store/privacy.html
- 📤 **دليل الرفع على Google Play:** `docs/publishing/GOOGLE_PLAY.md`

## Production architecture

Flutter → Supabase Auth / Data API / Realtime → PostgreSQL + RLS → Supabase Edge Functions

الأتمتة الخارجية:
Supabase automation_events → automation-worker → n8n → Google Sheets / WhatsApp / Image Studio عند تفعيلها.

## Production build checkpoint

يجب أن يمر قبل اعتبار النسخة قابلة للتشغيل:
1. `flutter pub get`
2. `flutter analyze`
3. `flutter test`
4. `flutter build web --release`
5. `flutter build apk --debug`

أي فشل في هذه السلسلة يمنع اعتبار النسخة إنتاجية.
