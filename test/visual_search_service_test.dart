import 'package:flutter_test/flutter_test.dart';

import 'package:alfaeq_yemen/services/visual_search_service.dart';

void main() {
  group('VisualSearchService.parseGuess', () {
    test('reads the product name from a JSON answer', () {
      expect(
        VisualSearchService.parseGuess('{"name":"أرز بسمتي","keywords":["أرز","بسمتي"]}'),
        'أرز بسمتي',
      );
    });

    test('reads the product name from a fenced JSON block', () {
      expect(
        VisualSearchService.parseGuess('```json\n{"name":"زيت ذرة","keywords":["زيت"]}\n```'),
        'زيت ذرة',
      );
    });

    test('falls back to keywords when the name is missing', () {
      expect(
        VisualSearchService.parseGuess('{"keywords":["ماء","معدني"]}'),
        'ماء معدني',
      );
    });

    test('takes the first line of a plain-text answer and strips quotes', () {
      expect(VisualSearchService.parseGuess('«شاي أحمر»\nملاحظة إضافية'), 'شاي أحمر');
      expect(VisualSearchService.parseGuess('- حليب طازج'), 'حليب طازج');
    });

    test('returns empty for an empty answer', () {
      expect(VisualSearchService.parseGuess(''), '');
      expect(VisualSearchService.parseGuess('   '), '');
    });

    test('keeps Arabic text intact', () {
      expect(VisualSearchService.parseGuess('{"name":"قهوة يمنية فاخرة"}'), 'قهوة يمنية فاخرة');
    });
  });
}
