import 'package:alfaeq_yemen/services/unsloth_ai_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UnslothAiService.describeError', () {
    test('maps rate limiting to Arabic guidance', () {
      final message = UnslothAiService.describeError({
        'error': 'ai_provider_rate_limited',
        'upstream_status': 429,
      });
      expect(message, contains('حد الطلبات'));
      expect(message, isNot(contains('ai_provider_rate_limited')));
    });

    test('maps provider auth failure and keeps the key hint', () {
      final message = UnslothAiService.describeError({'error': 'ai_provider_auth_failed'});
      expect(message, contains('مصادقة'));
    });

    test('maps a nested provider error object', () {
      final message = UnslothAiService.describeError({
        'error': {'message': 'ai_provider_not_configured'},
      });
      expect(message, contains('غير مهيأة'));
    });

    test('maps an empty provider reply to Arabic guidance', () {
      final message = UnslothAiService.describeError({'error': 'ai_provider_empty'});
      expect(message, contains('رداً صالحاً'));
      expect(message, isNot(contains('ai_provider_empty')));
    });

    test('falls back to the raw code when unknown', () {
      expect(UnslothAiService.describeError({'error': 'something_else'}), 'something_else');
    });

    test('falls back to a generic message for an empty payload', () {
      expect(UnslothAiService.describeError(null), 'فشل طلب بوابة الذكاء.');
    });
  });
}
