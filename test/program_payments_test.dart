import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardrails for in-mini-program payments (الدفع داخل البرامج المصغّرة).
void main() {
  group('mini-program payments', () {
    test('migration defines an additive, owner-safe payment RPC', () {
      final migration = File('supabase/migrations/20261101050000_mini_program_payments_v1.sql').readAsStringSync();
      expect(migration, contains('create table if not exists public.program_orders'));
      expect(migration, contains('alter table public.program_orders enable row level security'));
      expect(migration, contains('create or replace function public.pay_mini_program'));
      // Reuses the hardened wallet primitives + FX converter.
      expect(migration, contains('private.wallet_debit_internal'));
      expect(migration, contains('private.fx_convert'));
      // Idempotent + guarded.
      expect(migration, contains('invalid_idempotency_key'));
      expect(migration, contains('insufficient wallet balance'));
      expect(migration, contains('from public, anon'));
      // Direct writes are revoked; only the RPC writes.
      expect(migration, contains('revoke all on public.program_orders from public, anon'));
      // Receipts are private to the buyer/owner/staff.
      expect(migration, contains('program_orders_read'));
      expect(migration, contains('private.is_platform_staff()'));
    });

    test('service is RPC-first and the checkout page charges the wallet', () {
      final service = File('lib/services/program_payments_service.dart').readAsStringSync();
      expect(service, contains("rpc('pay_mini_program'"));
      expect(service, contains("from('program_orders')"));
      expect(service, contains('idempotencyKey'));

      final checkout = File('lib/screens/program_checkout_page.dart').readAsStringSync();
      expect(checkout, contains('ProgramPaymentsService'));
      expect(checkout, contains('ensureMyWallet'));

      final launcher = File('lib/screens/mini_programs_page.dart').readAsStringSync();
      expect(launcher, contains('ProgramCheckoutPage'));

      final profile = File('lib/screens/official_account_detail_page.dart').readAsStringSync();
      expect(profile, contains('ProgramCheckoutPage'));
      expect(profile, contains('_payProgram'));
    });
  });
}
