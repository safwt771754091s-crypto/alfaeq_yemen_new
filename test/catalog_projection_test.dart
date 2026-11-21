import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:alfaeq_yemen/services/catalog_service.dart';

/// PostgREST rejects the whole request when one selected column is unknown, so
/// a typo in the projection takes the storefront down instead of degrading it.
/// These tests pin the projection to the fields the UI actually reads.
void main() {
  group('catalog projections', () {
    test('product projection carries every field the storefront renders', () {
      const required = [
        'id',
        'name',
        'price',
        'currency',
        'stock',
        'image_url',
        'description',
        'section_id',
        'store_id',
        'status',
        'sale_unit',
        'stock_base',
      ];
      final columns = CatalogService.productColumnsForTest;
      for (final field in required) {
        expect(columns, contains(field), reason: '$field is read by the UI');
      }
    });

    test('store projection carries every field the store card renders', () {
      const required = ['id', 'name', 'address', 'phone', 'status'];
      final columns = CatalogService.storeColumnsForTest;
      for (final field in required) {
        expect(columns, contains(field), reason: '$field is read by the UI');
      }
    });

    test('product projection omits the import metadata blob', () {
      // About 700 bytes per row, and only the barcode is ever read. Barcode
      // search uses CatalogService.searchBarcode instead.
      expect(CatalogService.productColumnsForTest, isNot(contains('metadata')));
    });

    test('home page asks the server for in-stock rows only', () {
      // The featured grid shows 12 cards. Fetching 200 rows and filtering them
      // in Dart cost 103 KB and a longer query per home page visit.
      final source = File('lib/screens/world_home_page.dart').readAsStringSync();
      expect(source, contains('inStockOnly: true'));
      expect(source, isNot(contains('activeProducts(limit: 200)')));
    });

    test('stock filter is a real column so PostgREST can apply it', () {
      // Filtering on a column that does not exist fails the whole request.
      expect(CatalogService.productColumnsForTest, contains('stock_base'));
    });

    test('projections list no duplicate columns', () {
      for (final columns in [
        CatalogService.productColumnsForTest,
        CatalogService.storeColumnsForTest,
      ]) {
        expect(columns.toSet().length, columns.length);
      }
    });
  });
}
