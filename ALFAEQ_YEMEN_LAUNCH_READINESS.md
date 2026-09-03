# الفائق يمن — Launch Readiness

## تم تجهيزه في هذه المرحلة
- Flutter Android CI لا يحذف مجلد `android` الموجود، ويعيد إنشاءه فقط إذا كان مفقودًا.
- تفعيل Java 17 في البناء.
- تشغيل `flutter pub get` ثم `flutter analyze` قبل إنشاء APK.
- إنشاء APK تجريبي ورفعه كـ GitHub Actions artifact.
- تثبيت إصدار التطبيق الحالي على `1.0.9+2`.
- منع رفع ملفات مفاتيح توقيع Android و`key.properties` إلى Git.

## المتبقي قبل Google Play
1. ربط Firebase الحقيقي بدل ملف `firebase_options.dart` التجريبي.
2. التأكد من Android package/applicationId النهائي: `com.alfaeq.yemen`.
3. إعداد توقيع Release باستخدام المفتاح الموجود محليًا دون رفعه إلى GitHub.
4. إضافة GitHub Actions secrets اللازمة للتوقيع إذا كان البناء Release سيتم على GitHub.
5. إنشاء Android App Bundle (`.aab`) موقّع Release.
6. اختبار تسجيل الدخول، الصلاحيات، الطلبات، الدفع، QR، والإشعارات على جهاز Android حقيقي.
7. تجهيز بيانات Google Play: اسم التطبيق، الوصف، الأيقونة، لقطات الشاشة، سياسة الخصوصية، وتصنيف المحتوى.
8. رفع `.aab` إلى Google Play Console ثم اختبار المسار الداخلي قبل الإنتاج.

> لا يتم وضع كلمات المرور أو ملفات الشهادات أو مفاتيح Firebase السرية داخل المستودع.
