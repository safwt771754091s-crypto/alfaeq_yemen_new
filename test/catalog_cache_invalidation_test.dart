import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Caching the catalog for five minutes is only safe while every write path
/// drops the cache. Otherwise an edited price or stock level keeps showing the
/// old value until the TTL expires.
void main() {
  group('catalog cache invalidation', () {
    test('every product write path invalidates the catalog cache', () {
      const writers = {
        'lib/screens/product_edit_page.dart': "from('products').update(",
        'lib/screens/bulk_product_import_page.dart': "from('products').upsert(",
        'lib/screens/admin_data_entry.dart': "from('products').insert(",
        'lib/screens/merchant_center_page.dart': "from('products').insert(",
      };

      for (final entry in writers.entries) {
        final source = File(entry.key).readAsStringSync();
        expect(source, contains(entry.value), reason: '${entry.key} still writes products');
        expect(
          source,
          contains("QueryCache.instance.invalidate('catalog.')"),
          reason: '${entry.key} must drop the cached catalog after writing',
        );
      }
    });
  });
}
