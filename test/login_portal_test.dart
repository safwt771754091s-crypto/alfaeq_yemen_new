import 'package:flutter_test/flutter_test.dart';

import 'package:alfaeq_yemen/core/login_portal.dart';

void main() {
  group('loginPortalFromUri', () {
    test('detects the merchant portal from a fragment', () {
      expect(loginPortalFromUri(Uri.parse('https://app/#/merchant')),
          LoginPortal.merchant);
    });

    test('detects the driver portal from a query parameter', () {
      expect(loginPortalFromUri(Uri.parse('https://app/?portal=driver')),
          LoginPortal.driver);
      expect(loginPortalFromUri(Uri.parse('https://app/?role=courier')),
          LoginPortal.driver);
      expect(loginPortalFromUri(Uri.parse('https://app/?mode=delivery')),
          LoginPortal.driver);
    });

    test('supports Arabic keywords', () {
      expect(loginPortalFromUri(Uri.parse('https://app/?role=مندوب')),
          LoginPortal.driver);
      expect(loginPortalFromUri(Uri.parse('https://app/?role=تاجر')),
          LoginPortal.merchant);
    });

    test('returns null for the generic login', () {
      expect(loginPortalFromUri(Uri.parse('https://app/')), isNull);
      expect(loginPortalFromUri(Uri.parse('https://app/#/signup')), isNull);
    });
  });
}
