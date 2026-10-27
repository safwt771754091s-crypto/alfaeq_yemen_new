import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('master bank deposits migration', () {
    final sql = File('supabase/migrations/20261025040000_master_bank_deposits_v1.sql').readAsStringSync();
    test('creates the three required tables', () {
      for (final table in const ['master_bank_accounts', 'wallet_deposits', 'master_permissions']) {
        expect(sql, contains('create table if not exists public.$table'), reason: 'missing $table');
      }
    });

    test('seeds the three official Al-Kuraimi accounts', () {
      for (final account in const ['3009540813', '3065094443', '3065190868']) {
        expect(sql, contains(account), reason: 'missing account $account');
      }
      expect(sql, contains('بنك الكريمي'));
      for (final currency in const ['YER', 'SAR', 'USD']) {
        expect(sql, contains("('$currency'"), reason: 'missing currency $currency');
      }
    });

    test('exposes the deposit + permission RPCs the app calls', () {
      for (final fn in const [
        'public.wallet_deposit_create(',
        'public.wallet_deposits_list(',
        'public.wallet_deposit_decide(',
        'public.master_permissions_list(',
        'public.master_permission_set(',
        'public.has_master_permission(',
      ]) {
        expect(sql, contains(fn), reason: 'missing $fn');
      }
    });

    test('gates approval on the master owner and credits idempotently', () {
      expect(sql, contains('private.is_master_owner()'));
      expect(sql, contains("if not private.is_master_owner() then raise exception 'not_authorized'"));
      expect(sql, contains('private.deposit_credit'));
      expect(sql, contains("'deposit:' || p_deposit_id::text"));
    });

    test('RLS: owner-only writes, self-only inserts', () {
      expect(sql, contains('enable row level security'));
      expect(sql, contains('uid = auth.uid()::text and status = \'pending\''));
      expect(sql, contains('private.is_master_owner()'));
    });

    test('creates a private receipts bucket with owner-scoped storage policies', () {
      expect(sql, contains("'deposits', 'deposits', false"));
      expect(sql, contains('deposits_insert'));
      expect(sql, contains('storage.foldername(name)'));
    });
  });

  group('master deposits wiring', () {
    test('deposit service talks to the migration RPCs', () {
      final svc = File('lib/services/wallet_deposit_service.dart').readAsStringSync();
      for (final rpc in const [
        'wallet_deposit_create',
        'wallet_deposits_list',
        'wallet_deposit_decide',
        'master_bank_accounts',
      ]) {
        expect(svc, contains(rpc), reason: 'WalletDepositService must reference $rpc');
      }
    });

    test('deposit page shows accounts and the review page is owner-gated', () {
      final deposit = File('lib/screens/wallet_deposit_page.dart').readAsStringSync();
      expect(deposit, contains('رقم الإيصال'));
      expect(deposit, contains('إرفاق صورة السند'));
      // صورة السند إلزامية: الصفحة تمنع الإرسال بلا صورة.
      expect(deposit, contains('_receiptBytes == null'));
      expect(deposit, contains('صورة السند البنكي كإثبات'));
      // بطاقة الحساب المطلوب حسب العملة.
      expect(deposit, contains('_selectedAccountBanner'));

      final review = File('lib/screens/wallet_deposits_review_page.dart').readAsStringSync();
      expect(review, contains('hasOwnerClaim'));
      expect(review, contains('wallet_deposit_decide'));
    });

    test('entry points are wired into the account center and admin dashboard', () {
      expect(File('lib/screens/account_center_page.dart').readAsStringSync(), contains('WalletDepositPage'));
      expect(File('lib/screens/admin_dashboard.dart').readAsStringSync(), contains('WalletDepositsReviewPage'));
    });
  });

  group('deposit receipt is mandatory (proof of transfer)', () {
    final sql = File('supabase/migrations/20261028010000_wallet_deposit_receipt_required_v1.sql').readAsStringSync();

    test('makes receipt_url NOT NULL with a non-empty check', () {
      expect(sql, contains('alter column receipt_url set not null'));
      expect(sql, contains('wallet_deposits_receipt_url_present'));
      expect(sql, contains("check (btrim(receipt_url) <> '')"));
    });

    test('backfills legacy rows instead of dropping them', () {
      expect(sql, contains("where receipt_url is null or btrim(receipt_url) = ''"));
      expect(sql, contains('legacy:no-receipt-attached'));
    });

    test('RPC rejects a deposit without a receipt image', () {
      expect(sql, contains('wallet_deposit_create'));
      expect(sql, contains("raise exception 'receipt_image_required'"));
      expect(sql, contains("if v_url = '' then"));
    });
  });
}
