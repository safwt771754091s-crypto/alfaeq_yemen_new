import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:alfaeq_yemen/core/permission_catalog.dart';

void main() {
  group('permission catalog', () {
    test('covers the full platform permission set with unique ids', () {
      expect(PermissionCatalog.all.length, 36);
      final ids = PermissionCatalog.all.map((p) => p.id).toSet();
      expect(ids.length, PermissionCatalog.all.length, reason: 'duplicate permission id');
      // The legacy ten permissions must still be present.
      for (final legacy in const [
        'wallet.deposits.review',
        'wallet.deposits.reject',
        'wallet.withdraw.review',
        'wallet.adjust',
        'admin.dashboard',
        'admin.users.manage',
        'admin.merchants.approve',
        'admin.payouts.review',
        'platform.settings',
        'platform.bank_accounts.manage',
      ]) {
        expect(ids, contains(legacy), reason: 'missing legacy permission $legacy');
      }
    });

    test('every permission has an Arabic label and a labelled category', () {
      for (final p in PermissionCatalog.all) {
        expect(p.label.trim(), isNotEmpty, reason: '${p.id} has no label');
        expect(PermissionCatalog.categoryLabels.containsKey(p.category), isTrue,
            reason: '${p.id} has unlabelled category ${p.category}');
      }
      expect(PermissionCatalog.labelFor('products.manage'), 'إدارة الأصناف');
      expect(PermissionCatalog.labelFor('unknown.permission'), 'unknown.permission');
    });

    test('groups every permission under a category', () {
      final grouped = PermissionCatalog.byCategory;
      final total = grouped.values.fold<int>(0, (sum, list) => sum + list.length);
      expect(total, PermissionCatalog.all.length);
    });
  });

  group('permissions catalog migration', () {
    final sql = File('supabase/migrations/20261027020000_permissions_catalog_v1.sql').readAsStringSync();

    test('creates the readable catalog table', () {
      expect(sql, contains('create table if not exists public.permissions_catalog'));
      expect(sql, contains('alter table public.permissions_catalog enable row level security'));
    });

    test('grants the whole catalog to owner/admin accounts', () {
      expect(sql, contains('cross join public.permissions_catalog c'));
      expect(sql, contains('on conflict (uid, permission) do nothing'));
    });

    test('keeps new owner accounts fully granted via a trigger', () {
      expect(sql, contains('create or replace function private.grant_all_permissions_to_owner()'));
      expect(sql, contains('create trigger grant_all_permissions_on_owner'));
      expect(sql, contains('after insert or update of owner, admin, role on public.users'));
    });
  });

  group('pgroonga index repair migration', () {
    final sql = File('supabase/migrations/20261027010000_fix_pgroonga_search_indexes_v1.sql').readAsStringSync();

    test('rebuilds the stale search indexes idempotently', () {
      for (final idx in const [
        'public.products_name_pgroonga_idx',
        'public.products_description_pgroonga_idx',
        'public.stores_name_pgroonga_idx',
      ]) {
        expect(sql, contains(idx), reason: 'missing $idx');
      }
      expect(sql, contains("execute format('reindex index %s', idx)"));
      expect(sql, contains('analyze public.products'));
    });
  });

  group('owner product list reports the true total', () {
    test('merchant center asks the server for the exact count', () {
      final page = File('lib/screens/merchant_center_page.dart').readAsStringSync();
      expect(page, contains('CountOption.exact'));
      // The old hard cap that hid products behind a 150-row window is gone.
      expect(page, isNot(contains('const maxRows = 150')));
      expect(page, contains('إجمالي الأصناف'));
    });

    test('admin dashboard counts large tables with an exact count', () {
      final page = File('lib/screens/admin_dashboard.dart').readAsStringSync();
      expect(page, contains('Future<int> exactCount('));
      expect(page, contains("await exactCount(client.from('products').select('id'))"));
    });
  });

  group('permissions editor', () {
    test('reads and writes the master permission matrix', () {
      final editor = File('lib/screens/permissions_editor.dart').readAsStringSync();
      expect(editor, contains("from('master_permissions')"));
      expect(editor, contains("rpc('master_permission_set'"));
      expect(editor, contains('PermissionCatalog.byCategory'));
    });

    test('user management surfaces the full catalog', () {
      final page = File('lib/screens/admin_user_management_page.dart').readAsStringSync();
      expect(page, contains('PermissionCatalog.all'));
      expect(page, contains('showPermissionsEditor'));
    });
  });
}
