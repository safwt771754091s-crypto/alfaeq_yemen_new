import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardrails for the Official Account sales dashboard (لوحة مبيعات الحساب
/// الرسمي) and the seller-initiated refund.
void main() {
  group('account sales dashboard', () {
    test('migration adds owner-scoped RPCs and a safe refund', () {
      final m = File('supabase/migrations/20261101060000_account_sales_dashboard_v1.sql').readAsStringSync();
      expect(m, contains('create or replace function public.account_sales_summary'));
      expect(m, contains('create or replace function public.account_sales_orders'));
      expect(m, contains('create or replace function public.refund_program_order'));
      // Ownership guard on every RPC.
      expect(m, contains('not_account_owner'));
      // Refund reverses money atomically via the hardened wallet primitive.
      expect(m, contains('private.wallet_debit_internal'));
      expect(m, contains('insufficient_seller_balance'));
      // Buyer is notified of the refund.
      expect(m, contains('program_refund'));
      // No public/anon execute.
      expect(m, contains('from public, anon'));
      expect(m, contains('to authenticated, service_role'));
    });

    test('service and screen are wired for owners', () {
      final service = File('lib/services/account_sales_service.dart').readAsStringSync();
      expect(service, contains("rpc('account_sales_summary'"));
      expect(service, contains("rpc('account_sales_orders'"));
      expect(service, contains("rpc('refund_program_order'"));

      final screen = File('lib/screens/account_sales_page.dart').readAsStringSync();
      expect(screen, contains('AccountSalesService'));
      expect(screen, contains('استرداد'));

      final detail = File('lib/screens/official_account_detail_page.dart').readAsStringSync();
      expect(detail, contains('AccountSalesPage'));
      expect(detail, contains('لوحة المبيعات'));
    });
  });
}
