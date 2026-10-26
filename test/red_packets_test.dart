import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('red packets migration', () {
    final sql = File('supabase/migrations/20261026020000_red_packets_v1.sql').readAsStringSync();

    test('creates the packet + claims tables', () {
      expect(sql, contains('create table if not exists public.red_packets'));
      expect(sql, contains('create table if not exists public.red_packet_claims'));
    });

    test('enforces one claim per user and safe amounts', () {
      expect(sql, contains('unique (packet_id, uid)'));
      expect(sql, contains('check (total_amount > 0)'));
      expect(sql, contains('check (share_count between 1 and 100)'));
    });

    test('exposes create/open/details/claims/reclaim RPCs', () {
      for (final fn in const [
        'public.red_packet_create(',
        'public.red_packet_open(',
        'public.red_packet_details(',
        'public.red_packet_claims_list(',
        'public.red_packet_reclaim(',
      ]) {
        expect(sql, contains(fn), reason: 'missing $fn');
      }
    });

    test('moves money through the wallet ledger, never minting', () {
      expect(sql, contains('wallet_ledger'));
      expect(sql, contains("'rp-lock-'"));
      expect(sql, contains("'rp-claim-'"));
      expect(sql, contains("'rp-refund-'"));
      expect(sql, contains('insufficient_wallet_balance'));
    });

    test('RLS restricts packets to thread members and staff', () {
      expect(sql, contains('enable row level security'));
      expect(sql, contains('private.is_thread_member(thread_id)'));
      expect(sql, contains('private.is_platform_staff()'));
    });

    test('sweeps expired packets and guards the cron install', () {
      expect(sql, contains('private.red_packet_expire_sweep'));
      expect(sql, contains("cron.schedule("));
      expect(sql, contains("'alfaeq-red-packet-expire'"));
    });
  });

  group('red packets wiring', () {
    test('service talks to the migration RPCs', () {
      final svc = File('lib/services/red_packet_service.dart').readAsStringSync();
      for (final rpc in const [
        'red_packet_create',
        'red_packet_open',
        'red_packet_details',
        'red_packet_claims_list',
        'red_packet_reclaim',
      ]) {
        expect(svc, contains(rpc), reason: 'RedPacketService must reference $rpc');
      }
    });

    test('chat screens render and send red packets', () {
      final direct = File('lib/screens/contacts_page.dart').readAsStringSync();
      expect(direct, contains('RedPacketPage'));
      expect(direct, contains('showSendRedPacketSheet'));

      final group = File('lib/screens/group_chat_page.dart').readAsStringSync();
      expect(group, contains('RedPacketPage'));
      expect(group, contains('showSendRedPacketSheet'));

      final page = File('lib/screens/red_packet_page.dart').readAsStringSync();
      expect(page, contains('افتح الحزمة'));
      expect(page, contains('سجل الفتح'));
    });
  });
}
