import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the public product gallery that is committed to the repository and
/// published on GitHub Pages. A broken or drifted snapshot would hide products
/// from the owner, so the files must stay valid and mutually consistent.
void main() {
  group('public product gallery', () {
    test('products.json and missing-images.json are valid and consistent', () {
      final productsFile = File('catalog/products.json');
      final missingFile = File('catalog/missing-images.json');
      expect(productsFile.existsSync(), isTrue, reason: 'catalog/products.json must be committed');
      expect(missingFile.existsSync(), isTrue, reason: 'catalog/missing-images.json must be committed');

      final products = (jsonDecode(productsFile.readAsStringSync()) as List).cast<Map<String, dynamic>>();
      final missing = (jsonDecode(missingFile.readAsStringSync()) as List).cast<Map<String, dynamic>>();
      expect(products, isNotEmpty);

      for (final product in products) {
        expect(product['id'], isA<String>());
        expect(product['id'], isNotEmpty);
        expect(product.containsKey('image'), isTrue);
      }

      final missingIds = missing.map((p) => p['id']).toSet();
      final expectedMissing = products.where((p) => (p['image'] as String?)!.isEmpty).map((p) => p['id']).toSet();
      expect(missingIds, equals(expectedMissing), reason: 'missing-images.json must match products with an empty image');
    });

    test('the committed gallery exposes images plus a missing image placeholder', () {
      final html = File('catalog/index.html').readAsStringSync();
      expect(html, contains('كتالوج الفائق يمن'));
      expect(html, contains('ينقص صورة'));
      expect(html, contains('data-state="missing"'));
    });

    test('the builder is wired into the Pages deploy and the refresh workflow', () {
      final build = File('.github/workflows/flutter_build.yml').readAsStringSync();
      expect(build, contains('tools/build_product_gallery.py'));
      expect(build, contains('build/web/catalog'));

      final refresh = File('.github/workflows/product-gallery.yml').readAsStringSync();
      expect(refresh, contains('tools/build_product_gallery.py'));
    });
  });
}
