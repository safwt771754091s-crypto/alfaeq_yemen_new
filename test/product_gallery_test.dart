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

    test('the store download never pins a version and the QR codes stay fresh', () {
      final html = File('store/site/index.html').readAsStringSync();
      expect(html, contains('/releases/latest/download/app-release.apk'));
      // A pinned /releases/download/vX.Y.Z/ link would freeze the audience on an
      // old build, so the store page must not reference one.
      expect(RegExp(r'/releases/download/v\d').hasMatch(html), isFalse,
          reason: 'store page must not pin a release version');
      expect(html, isNot(contains('tinyurl.com')));

      final build = File('.github/workflows/flutter_build.yml').readAsStringSync();
      expect(build, contains('tools/build_store_qr.py'),
          reason: 'the QR codes must be regenerated during deploy');
    });
  });

  group('shareable ad link and brand logo', () {
    test('the store landing page shows the brand logo and links the share page', () {
      final html = File('store/site/index.html').readAsStringSync();
      expect(html, contains('logo.png'), reason: 'the logo image must be shown');
      expect(html, contains('share.html'), reason: 'the landing page must link the share page');
      expect(html, contains('og:image'), reason: 'sharing needs a social preview image');
    });

    test('the share page exists, carries the logo and opens the app', () {
      final file = File('store/site/share.html');
      expect(file.existsSync(), isTrue, reason: 'store/site/share.html must be committed');
      final html = file.readAsStringSync();
      expect(html, contains('logo.png'), reason: 'the share page must show the logo');
      expect(html, contains('https://safwt771754091s-crypto.github.io/alfaeq_yemen_new/'),
          reason: 'the share page must expose the app link');
      expect(html, contains('wa.me/?text='), reason: 'WhatsApp sharing must be wired');
      expect(html, contains('?portal=merchant'), reason: 'the merchant link must be offered');
      expect(html, contains('?portal=driver'), reason: 'the driver link must be offered');
      // A pinned version link would freeze the audience on an old build.
      expect(RegExp(r'/releases/download/v\d').hasMatch(html), isFalse,
          reason: 'the share page must not pin a release version');
    });

    test('the web entry uses the logo and exposes social metadata', () {
      final html = File('web/index.html').readAsStringSync();
      expect(html, contains('logo.png'), reason: 'the loading screen must show the logo');
      expect(html, contains('og:image'), reason: 'the web app needs a social preview image');
      expect(html, contains('twitter:card'), reason: 'the web app needs a Twitter card');
      for (final asset in ['store/site/logo.svg', 'store/site/logo.png', 'store/site/ad-banner.png']) {
        expect(File(asset).existsSync(), isTrue, reason: '$asset must be committed');
      }
      // web/ is gitignored, so the deploy must copy the logo into the build.
      final build = File('.github/workflows/flutter_build.yml').readAsStringSync();
      expect(build, contains('cp -f store/site/logo.png build/web/logo.png'),
          reason: 'the deploy must copy the logo into the published web root');
    });

    test('the deploy publishes the logo and share page', () {
      final build = File('.github/workflows/flutter_build.yml').readAsStringSync();
      expect(build, contains('store/site/share.html'));
      expect(build, contains('store/site/logo.png'));
      expect(build, contains('store/site/ad-banner.png'));
    });
  });
}
