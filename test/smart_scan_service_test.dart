import 'package:flutter_test/flutter_test.dart';

import 'package:alfaeq_yemen/services/smart_scan_service.dart';

/// The classifier must be pure and offline-safe: Supabase is not initialized
/// in tests, so payment/store/link codes are decided locally and barcodes fall
/// through to a text search without touching the network.
void main() {
  const service = SmartScanService();

  group('SmartScanService', () {
    test('recognises an Alfaeq payment code', () async {
      final result = await service.resolve('alfaeq://pay?uid=abc-123&name=Ali');
      expect(result.kind, SmartScanKind.payment);
      expect(result.uid, 'abc-123');
    });

    test('recognises a store deep link by query and by path', () async {
      final byQuery = await service.resolve('alfaeq://store?id=store-1');
      expect(byQuery.kind, SmartScanKind.store);
      expect(byQuery.storeId, 'store-1');

      final byPath = await service.resolve('alfaeq://store/store-2');
      expect(byPath.kind, SmartScanKind.store);
      expect(byPath.storeId, 'store-2');
    });

    test('recognises plain web links', () async {
      final https = await service.resolve('https://example.com/promo');
      expect(https.kind, SmartScanKind.url);
      expect(https.url, 'https://example.com/promo');

      final http = await service.resolve('http://example.com');
      expect(http.kind, SmartScanKind.url);
    });

    test('falls back to search for an unknown barcode', () async {
      final result = await service.resolve('6291100123456');
      expect(result.kind, SmartScanKind.search);
      expect(result.raw, '6291100123456');
    });

    test('empty input is a search with the raw value preserved', () async {
      final result = await service.resolve('   ');
      expect(result.kind, SmartScanKind.search);
      expect(result.raw, '');
    });
  });
}
