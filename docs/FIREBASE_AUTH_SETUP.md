# إعداد Firebase Authentication — الفائق يمن

هذا المستودع يستخدم `firebase_core` و`firebase_auth`، وتسجيل الدخول الحالي يعتمد على رقم الهاتف وSMS.

## 1. مشروع Firebase

استخدم مشروع Firebase الحالي:

`alfaeq-yemen-fed37`

لا تنشئ مشروعًا جديدًا.

## 2. تفعيل Phone Authentication

من Firebase Console:

1. افتح Authentication.
2. افتح Sign-in method.
3. فعّل Phone.
4. تأكد من إعدادات الدول/أرقام الاختبار المناسبة أثناء مرحلة الاختبار.

## 3. إعداد تطبيق Android

يجب أن يكون Android `applicationId` النهائي:

`com.alfaeq.yemen`

ويجب تسجيل هذا التطبيق داخل Firebase قبل اختبار تسجيل الدخول الحقيقي.

أضف SHA-1 وSHA-256 لشهادة التطبيق التي سيُبنى بها APK الاختبار، لأن Firebase Phone Authentication على Android قد يحتاجها للتحقق من التطبيق.

## 4. ملف Firebase Flutter

شغّل `flutterfire configure` من جذر مشروع Flutter بعد تثبيت Firebase CLI الرسمي، واختر المشروع `alfaeq-yemen-fed37` وتطبيق Android الصحيح.

سينتج الملف:

`lib/core/firebase/firebase_options.dart`

لا تضع كلمات مرور أو مفاتيح خدمة Service Account داخل GitHub.

## 5. GitHub Actions

Workflow البناء يدعم Secret باسم:

`FIREBASE_OPTIONS_DART`

ضع فيه **المحتوى الكامل** لملف `firebase_options.dart` الناتج من FlutterFire.

أثناء بناء APK، سيتم حقن الملف داخل بيئة البناء فقط. ملف المستودع الأساسي يبقى Placeholder عندما لا يكون الـSecret موجودًا.

## 6. الاختبار

بعد إعداد الـSecret وتشغيل Workflow:

1. ثبّت APK الناتج من GitHub Actions.
2. افتح الفائق يمن.
3. افتح تسجيل الدخول.
4. أدخل رقم الهاتف بصيغة دولية مناسبة.
5. اطلب رمز SMS.
6. أدخل الرمز.
7. تحقق من انتقال الحساب إلى الحالة المسجلة الدخول.
8. اختبر تسجيل الخروج ثم تسجيل الدخول مرة أخرى.

## ملاحظة أمنية

لا ترسل إلى المحادثة كلمة مرور Firebase أو Google أو GitHub، ولا ترفع keystore أو `key.properties` أو Service Account JSON إلى المستودع العام.
