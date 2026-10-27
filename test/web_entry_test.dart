import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// يضمن أن صفحة الويب العامة تحمي تجربة المستخدم على الشبكات البطيئة:
/// شاشة تحميل تظهر فوراً، وتحويل روابط الدور `#/driver` إلى `?portal=...`
/// قبل إقلاع محرك Flutter (المحرك يمسح أسماء المسارات المجهولة).
void main() {
  late String html;

  setUpAll(() {
    final file = File('web/index.html');
    expect(file.existsSync(), isTrue, reason: 'web/index.html مفقود');
    html = file.readAsStringSync();
  });

  test('يعرض شاشة تحميل قبل إقلاع المحرك ويخفيها عند أول إطار', () {
    expect(html.contains('id="alfaeq-loader"'), isTrue,
        reason: 'شاشة التحميل مفقودة؛ سيرى المستخدم صفحة بيضاء على الشبكات البطيئة');
    expect(html.contains("addEventListener('flutter-first-frame'"), isTrue,
        reason: 'شاشة التحميل لا تُخفى عند أول إطار من التطبيق');
    expect(html.contains('جارٍ تجهيز التطبيق'), isTrue,
        reason: 'نص شاشة التحميل بالعربية مفقود');
  });

  test('يحوّل روابط الدور من #/driver إلى ?portal= قبل إقلاع المحرك', () {
    expect(html.contains("params.set('portal'"), isTrue,
        reason: 'لا يوجد تحويل لروابط الدور إلى صيغة الاستعلام التي يقرأها التطبيق');
    expect(html.contains('history.replaceState'), isTrue,
        reason: 'يجب استبدال الرابط قبل أن يمسحه محرك Flutter');
    expect(html.contains('driver|courier|delivery'), isTrue,
        reason: 'كلمات المندوب المفتاحية مفقودة');
    expect(html.contains('merchant|vendor|seller'), isTrue,
        reason: 'كلمات التاجر المفتاحية مفقودة');
    expect(html.contains('merchant_invite'), isTrue,
        reason: 'يجب حماية رابط دعوة التاجر من إعادة الكتابة');
  });
}
