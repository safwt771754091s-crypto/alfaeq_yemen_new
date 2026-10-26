import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('merchant/driver applications migration', () {
    final sql = File('supabase/migrations/20261026010000_merchant_driver_applications_v1.sql').readAsStringSync();

    test('creates both application tables', () {
      for (final table in const ['merchant_applications', 'driver_applications']) {
        expect(sql, contains('create table if not exists public.$table'), reason: 'missing $table');
      }
    });

    test('enforces one pending application per user', () {
      expect(sql, contains('merchant_applications_one_pending_idx'));
      expect(sql, contains('driver_applications_one_pending_idx'));
      expect(sql, contains("where status = 'pending'"));
    });

    test('exposes submit/decide/cancel RPCs for both roles', () {
      for (final fn in const [
        'public.merchant_application_submit(',
        'public.merchant_application_decide(',
        'public.merchant_application_cancel(',
        'public.driver_application_submit(',
        'public.driver_application_decide(',
        'public.driver_application_cancel(',
      ]) {
        expect(sql, contains(fn), reason: 'missing $fn');
      }
    });

    test('gates approval on platform staff', () {
      expect(sql, contains('if not private.is_platform_staff() then raise exception \'not_authorized\''));
      expect(sql, contains('private.notify_user('));
    });

    test('approval performs the real side effects', () {
      expect(sql, contains('insert into public.stores'));
      expect(sql, contains("update public.users set role = 'merchant'"));
      expect(sql, contains('insert into public.drivers'));
      expect(sql, contains("update public.users set role = 'driver'"));
    });

    test('RLS: owner-or-staff read, self-only pending insert', () {
      expect(sql, contains('enable row level security'));
      expect(sql, contains("uid = auth.uid()::text or private.is_platform_staff()"));
      expect(sql, contains("uid = auth.uid()::text and status = 'pending'"));
    });
  });

  group('merchant/driver applications wiring', () {
    test('application service talks to the migration RPCs', () {
      final svc = File('lib/services/application_service.dart').readAsStringSync();
      for (final rpc in const [
        'merchant_application_submit',
        'merchant_application_decide',
        'driver_application_submit',
        'driver_application_decide',
        'merchant_applications',
        'driver_applications',
      ]) {
        expect(svc, contains(rpc), reason: 'ApplicationService must reference $rpc');
      }
    });

    test('customer entry points are wired into the account center', () {
      final account = File('lib/screens/account_center_page.dart').readAsStringSync();
      expect(account, contains('MerchantApplicationPage'));
      expect(account, contains('DriverApplicationPage'));
      expect(account, contains('انضم كتاجر'));
      expect(account, contains('انضم كمندوب توصيل'));
    });

    test('staff review queues are wired into the admin dashboard', () {
      final admin = File('lib/screens/admin_dashboard.dart').readAsStringSync();
      expect(admin, contains('MerchantApplicationsReviewPage'));
      expect(admin, contains('DriverApplicationsReviewPage'));
    });
  });
}
