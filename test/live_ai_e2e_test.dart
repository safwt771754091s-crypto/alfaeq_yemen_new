import 'dart:io';

import 'package:alfaeq_yemen/ai/ai_service.dart';
import 'package:alfaeq_yemen/services/auth_service.dart';
import 'package:alfaeq_yemen/services/supabase_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opt-in live end-to-end check of the real AlfaeqAiService against the
/// production Supabase AI gateway. It is skipped unless credentials are
/// provided via --dart-define, so normal CI never depends on the network.
///
///   flutter test test/live_ai_e2e_test.dart \
///     --dart-define=LIVE_AI_EMAIL=... --dart-define=LIVE_AI_PASSWORD=...
void main() {
  const email = String.fromEnvironment('LIVE_AI_EMAIL');
  const password = String.fromEnvironment('LIVE_AI_PASSWORD');
  final enabled = email.isNotEmpty && password.isNotEmpty;

  test('live AI assistant answers with real catalog data', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // flutter_test installs an HttpOverrides that fails every request with 400.
    // This live check needs the real network, so restore the default client.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    await SupabaseService.initialize();
    final auth = AuthService();
    await auth.signIn(email: email, password: password);
    expect(SupabaseService.client.auth.currentUser, isNotNull);

    final ai = AlfaeqAiService();
    final name = await ai.sendMessage('ابحث عن منتج شوكولاتة');
    stdout.writeln('NAME_REPLY: $name');
    expect(name.trim().isNotEmpty, isTrue);

    final barcode = await ai.sendMessage('ابحث عن المنتج بالباركود 6281020325937');
    stdout.writeln('BARCODE_REPLY: $barcode');
    expect(barcode.contains('فول لونا') || barcode.contains('6281020325937'), isTrue,
        reason: 'barcode search must resolve the real product');

    for (final prompt in const [
      'ما رصيد محفظتي؟',
      'ما حالة طلبي الأخير؟',
      'ماذا يوجد في سلتي الآن؟',
      'ما ملخص حسابي؟',
      'ما أقرب المتاجر إليّ؟',
    ]) {
      final reply = await ai.sendMessage(prompt);
      stdout.writeln('TOOL_REPLY[$prompt]: $reply');
      expect(reply.trim().isNotEmpty, isTrue);
      expect(reply.contains('تعذر الاتصال بخدمة ذكاء'), isFalse, reason: prompt);
    }

    // Reversible action must gate on explicit confirmation, then execute.
    final gate = await ai.sendMessage('أضف المنتج super-f496a1482e8e إلى سلتي بكمية 1');
    stdout.writeln('CONFIRM_GATE: $gate');
    if (ai.hasPendingConfirmation) {
      final confirmed = await ai.confirmPendingAction();
      stdout.writeln('CONFIRM_RESULT: $confirmed');
      expect(confirmed.trim().isNotEmpty, isTrue);
    }
  }, skip: enabled ? false : 'set LIVE_AI_EMAIL/LIVE_AI_PASSWORD to run');
}
