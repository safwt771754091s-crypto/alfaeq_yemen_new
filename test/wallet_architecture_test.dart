import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wallet foundation is server-authoritative', () {
    final rules = File('firestore.rules').readAsStringSync();
    expect(rules, contains("match /wallets/{uid}"));
    expect(rules, contains("allow update, delete: if staff();"));
    expect(rules, contains("match /walletTransactions/{id}"));
    expect(rules, contains("allow update, delete: if false;"));
    expect(rules, contains("match /walletOperations/{id}"));
    expect(rules, contains("request.resource.data.status == 'pending'"));
  });

  test('wallet service never writes monetary balances from client operations', () {
    final source = File('lib/services/wallet_service.dart').readAsStringSync();
    expect(source, contains("availableBalance': 0"));
    expect(source, contains("reservedBalance': 0"));
    expect(source, isNot(contains('availableBalance: amount')));
  });

  test('Super App sections contain live approved store queries', () {
    final source = File('lib/screens/super_app_sections_page.dart').readAsStringSync();
    expect(source, contains("collection('stores')"));
    expect(source, contains("where('status', isEqualTo: 'approved')"));
    expect(source, contains('SliverGrid'));
    expect(source, contains('ChoiceChip'));
  });
}
