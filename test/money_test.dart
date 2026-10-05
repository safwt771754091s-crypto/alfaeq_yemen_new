import 'package:alfaeq_yemen/core/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatAmount', () {
    test('keeps whole amounts compact', () {
      expect(formatAmount(5), '5');
      expect(formatAmount(17.0), '17');
      expect(formatAmount(100), '100');
    });

    test('keeps decimals for fractional catalog prices', () {
      expect(formatAmount(8.85), '8.85');
      expect(formatAmount(0.57), '0.57');
      expect(formatAmount(1.15), '1.15');
    });

    test('trims trailing zeros without losing significant digits', () {
      expect(formatAmount(1.5), '1.5');
      expect(formatAmount(2.10), '2.1');
    });
  });

  group('formatMoney', () {
    test('appends the real currency', () {
      expect(formatMoney(8.85, 'USD'), '8.85 USD');
      expect(formatMoney(5, 'YER'), '5 YER');
    });

    test('falls back for missing or non-positive amounts', () {
      expect(formatMoney(null, 'USD'), 'عند الطلب');
      expect(formatMoney(0, 'USD'), 'عند الطلب');
    });
  });
}
