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
    expect(rules, contains("request.resource.data.currency == 'YER'"));
    expect(rules, contains("request.resource.data.createdAt == request.time"));
    expect(rules, contains("keys().hasOnly(['type', 'recipientUid', 'amount', 'uid', 'status', 'currency', 'createdAt'])"));
    expect(rules, contains("request.resource.data.recipientUid != request.auth.uid"));
    expect(rules, contains("allow update, delete: if false;"));
  });

  test('wallet service never writes monetary balances from client operations', () {
    final source = File('lib/services/wallet_service.dart').readAsStringSync();
    expect(source, contains("availableBalance': 0"));
    expect(source, contains("reservedBalance': 0"));
    expect(source, contains("'type': 'transfer'"));
    expect(source, contains("'status': 'pending'"));
    expect(source, isNot(contains('availableBalance: amount')));
  });

  test('trusted wallet backend is idempotent and transactional', () {
    final source = File('functions/index.js').readAsStringSync();
    expect(source, contains("onDocumentCreated"));
    expect(source, contains("retry: true"));
    expect(source, contains("runTransaction"));
    expect(source, contains("INSUFFICIENT_FUNDS"));
    expect(source, contains("transfer_debit"));
    expect(source, contains("transfer_credit"));
    expect(source, contains("wallet_backend"));
  });

  test('Super App sections contain live approved store queries', () {
    final source = File('lib/screens/super_app_sections_page.dart').readAsStringSync();
    expect(source, contains("collection('stores')"));
    expect(source, contains("where('status', isEqualTo: 'approved')"));
    expect(source, contains('SliverGrid'));
    expect(source, contains('ChoiceChip'));
  });
}
