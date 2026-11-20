import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// SQL line comments describe the defect they repair, so assertions about the
/// executable contract must ignore them.
String _code(String sql) => sql
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('--'))
    .join('\n');

void main() {
  group('anonymous storefront access', () {
    final storefront = File(
      'supabase/migrations/20261121030000_restore_anon_storefront_v1.sql',
    ).readAsStringSync();
    final storefrontCode = _code(storefront);

    test('grants schema USAGE and EXECUTE so RLS can evaluate for anon', () {
      // 142 policies call private.is_platform_staff(); without schema USAGE the
      // call fails with "permission denied for function" and the public
      // storefront returns 401 for every signed-out visitor.
      expect(storefront, contains('grant usage on schema private to anon'));
      expect(
        storefront,
        contains('grant execute on function private.is_platform_staff() to anon'),
      );
    });

    test('only touches the staff predicate, never grants table access', () {
      expect(storefrontCode, isNot(contains('grant select')));
      expect(storefrontCode, isNot(contains('grant insert')));
      expect(storefrontCode, isNot(contains('grant update')));
      expect(storefrontCode, isNot(contains('grant delete')));
      expect(storefrontCode, isNot(contains('grant all')));
      expect(storefrontCode, isNot(contains('to authenticated')));
    });

    test('is idempotent so a re-run cannot fail', () {
      expect(storefrontCode, isNot(contains('revoke')));
    });
  });

  group('assign_order_driver contract', () {
    final sql = File(
      'supabase/migrations/20261121020000_assign_order_driver_contract_v1.sql',
    ).readAsStringSync();
    final sqlCode = _code(sql);

    test('drops before recreating so a return-type change is allowed', () {
      // 20260922190300 defined it as jsonb and 20260925020000 redefined it as
      // boolean with CREATE OR REPLACE, which aborts on an existing jsonb
      // definition.
      expect(sql, contains('drop function if exists public.assign_order_driver(text, text)'));
      expect(sql, contains('create or replace function public.assign_order_driver'));
    });

    test('returns jsonb, matching the original definition', () {
      expect(sqlCode, contains('returns jsonb'));
      expect(sqlCode, isNot(contains('returns boolean')));
    });

    test('never casts the jsonb result to boolean', () {
      // jsonb has no cast to boolean, so ::boolean raised at runtime and broke
      // every courier assignment and dispatch.
      expect(sqlCode, isNot(contains('::boolean')));
    });

    test('stays an invoker wrapper and keeps anon out', () {
      expect(sqlCode, contains('security invoker'));
      expect(sqlCode, contains("set search_path = ''"));
      expect(sql, contains('revoke all on function public.assign_order_driver(text, text) from public, anon'));
      expect(sql, contains('grant execute on function public.assign_order_driver(text, text) to authenticated'));
    });
  });
}
