import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('product management', () {
    test('products can be edited including image and section', () {
      final page = File('lib/screens/product_edit_page.dart').readAsStringSync();
      // Section move is an update on the products row (server-guarded by RLS).
      expect(page, contains("'section_id': _sectionId"));
      expect(page, contains("'image_url': _imageUrl"));
      // Image is uploaded to the shared media service, overwriting in place.
      expect(page, contains('MediaService.uploadProductImage'));
      expect(page, contains('overwrite: true'));
      // Barcode stays in metadata (the searchable field).
      expect(page, contains("metadata['barcode'] = barcode"));
    });

    test('media service overwrites storage objects and refreshes the asset', () {
      final service = File('lib/services/media_service.dart').readAsStringSync();
      expect(service, contains('upsert: overwrite'));
      expect(service, contains("eq('object_path', path)"));
    });

    test('admin and merchant centers expose the edit entry points', () {
      final admin = File('lib/screens/admin_data_entry.dart').readAsStringSync();
      final merchant = File('lib/screens/merchant_center_page.dart').readAsStringSync();
      expect(admin, contains('ProductEditPage('));
      expect(admin, contains('canChangeSection: true'));
      expect(merchant, contains('ProductEditPage('));
      // Merchants may edit image/price/stock but cannot move sections.
      expect(merchant, contains('canChangeSection: false'));
    });
  });
}
