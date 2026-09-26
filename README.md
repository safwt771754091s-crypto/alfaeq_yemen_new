# الفائق يمن — منصة إنتاجية مبنية على Supabase

المستودع الرسمي لمنصة الفائق يمن. البنية الحالية تعتمد **Supabase فقط** كطبقة الخلفية: Auth وPostgreSQL وRLS وRealtime وEdge Functions وStorage عند الحاجة.

- Web وAndroid مبنيان من نفس commit.
- لا يعتمد التطبيق على Firebase أو Firestore أو Cloud Functions.
- بيانات المتاجر والمنتجات والسلة والطلبات والحسابات محفوظة في Supabase الإنتاجي.
- لا توجد بيانات تجريبية تُعامل كبيانات إنتاجية.

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
