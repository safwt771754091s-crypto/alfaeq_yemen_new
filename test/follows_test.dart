import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('follows migration', () {
    final sql = File('supabase/migrations/20261025030000_follows_v1.sql').readAsStringSync();

    test('creates the follows table with a store/user target and RLS', () {
      expect(sql, contains('create table if not exists public.follows'));
      expect(sql, contains("target_type in ('store', 'user')"));
      expect(sql, contains('alter table public.follows enable row level security'));
    });

    test('exposes the RPCs the app calls', () {
      for (final fn in const [
        'public.follow_toggle(',
        'public.follow_state(',
        'public.my_follows(',
      ]) {
        expect(sql, contains(fn), reason: 'missing $fn');
      }
    });

    test('keeps follower counts in sync and grants only to authenticated', () {
      expect(sql, contains('follow_count_sync'));
      expect(sql, contains('follows_count after insert or delete'));
      expect(sql, contains('to authenticated'));
      expect(sql, isNot(contains('grant execute on function public.follow_toggle(text, text) to anon')));
    });
  });

  group('follows wiring', () {
    test('follow service talks to the migration RPCs', () {
      final svc = File('lib/services/follow_service.dart').readAsStringSync();
      for (final rpc in const ['follow_toggle', 'follow_state', 'my_follows']) {
        expect(svc, contains(rpc), reason: 'FollowService must call $rpc');
      }
    });

    test('store page shows a follow button and the account center links follows', () {
      final store = File('lib/screens/store_detail_page.dart').readAsStringSync();
      expect(store, contains('FollowButton(targetType: \'store\''));

      final account = File('lib/screens/account_center_page.dart').readAsStringSync();
      expect(account, contains('MyFollowsPage'));
    });
  });
}
