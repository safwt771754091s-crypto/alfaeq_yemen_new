import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Alfaeq Yemen commercial security architecture', () {
    test('merchant portal remains role-gated', () {
      final source = File('lib/screens/merchant_portal_page.dart').readAsStringSync();
      expect(source, contains("import '../services/auth_service.dart';"));
      expect(source, contains("role == 'merchant'"));
      expect(source, contains("role == 'admin'"));
      expect(source, contains("role == 'owner'"));
      expect(source, contains('const MerchantCenterPage()'));
      expect(source, contains('const MerchantOrdersPage()'));
    });

    test('merchant orders use Supabase ownership and server-side transitions', () {
      final orders = File('lib/screens/merchant_orders_page.dart').readAsStringSync();
      final migration = File('supabase/migrations/20260923160000_stage4_merchant_order_transitions.sql').readAsStringSync();
      expect(orders, contains("from('stores').select('id').eq('owner_id',uid)"));
      expect(orders, contains("rpc('transition_order'"));
      expect(migration, contains('security definer'));
      expect(migration, contains('s.owner_id = uid'));
      expect(migration, contains("raise exception 'not authorized'"));
      expect(migration, contains("raise exception 'invalid merchant order transition'"));
    });

    test('order creation stays on the Supabase transactional RPC', () {
      final orders = File('lib/services/order_service.dart').readAsStringSync();
      final migration = File('supabase/migrations/20260922190300_production_rpc_hardening.sql').readAsStringSync();
      expect(orders, contains("rpc('create_order'"));
      expect(migration, contains('create or replace function public.create_order'));
      expect(migration, contains('automation_event_inbox'));
    });

    test('commercial notifications stay on Supabase', () {
      final page = File('lib/screens/notifications_page.dart').readAsStringSync();
      expect(page, contains("from('notifications')"));
      expect(page, contains("read_at"));
    });

    test('the commercial app does not expose the future builder UI', () {
      final main = File('lib/main.dart').readAsStringSync();
      final home = File('lib/screens/world_home_page.dart').readAsStringSync();
      expect(main, isNot(contains('AiAssistantPage')));
      expect(home, isNot(contains('AiAssistantPage')));
    });
  });
}
