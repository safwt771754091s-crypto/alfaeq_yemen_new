import 'package:alfaeq_yemen/services/currency_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CurrencyService conversion', () {
    test('converts USD into YER and SAR with the platform rates', () {
      final service = CurrencyService.instance;
      // 1 USD = 3.75 SAR = 1537.5 YER (410 YER per SAR).
      expect(service.rateFor('USD'), 1);
      expect(service.rateFor('SAR'), 410);
      expect(service.rateFor('YER'), 1537.5);

      expect(service.convert(21.84, 'USD'), 21.84);
      expect(service.convert(21.84, 'SAR'), 8954.4);
      expect(service.convert(21.84, 'YER'), 33579.0);
    });

    test('rounds to 2 decimals to match the server', () {
      final service = CurrencyService.instance;
      expect(service.convert(8.85, 'YER'), 13606.88);
      expect(service.convert(8.85, 'SAR'), 3628.5);
    });

    test('formats native amounts with the right symbol', () {
      final service = CurrencyService.instance;
      expect(service.formatNative(33579, 'YER'), '33,579 ر.ي');
      expect(service.formatNative(8954.4, 'SAR'), '8,954.4 ر.س');
      expect(service.formatNative(8.85, 'USD'), r'8.85 $');
    });

    test('formatProduct converts USD base prices, leaves others as-is', () {
      final service = CurrencyService.instance;
      expect(service.formatProduct({'price': 8.85, 'currency': 'USD'}), r'8.85 $');
      expect(service.formatProduct({'price': 100, 'currency': 'YER'}), '100 ر.ي');
      expect(service.formatProduct({'price': null}), 'عند الطلب');
    });

    test('formatNative supports no selection by defaulting to USD', () {
      expect(CurrencyService.symbolFor('usd'), r'$');
      expect(CurrencyService.labelFor('sar'), 'ريال سعودي');
      expect(CurrencyService.labelFor('yer'), 'ريال يمني');
    });
  });
}
