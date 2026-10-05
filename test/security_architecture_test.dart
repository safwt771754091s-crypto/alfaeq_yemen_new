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
    });

    test('commercial notifications stay on Supabase', () {
      final page = File('lib/screens/notifications_page.dart').readAsStringSync();
      expect(page, contains("from('notifications')"));
      expect(page, contains("read_at"));
    });


    test('commercial support chat uses server-side RPCs', () {
      final page = File('lib/screens/support_chat_page.dart').readAsStringSync();
      expect(page, contains("rpc('create_support_thread'"));
      expect(page, contains("rpc('send_chat_message'"));
      expect(page, contains("from('chat_messages')"));
    });

    test('commercial app exposes Alfaeq Intelligence only as the user execution assistant', () {
      final home = File('lib/screens/world_home_page.dart').readAsStringSync();
      final ai = File('lib/screens/ai_assistant_page.dart').readAsStringSync();
      expect(home, contains("import 'ai_assistant_page.dart';"));
      expect(home, contains('AiAssistantPage()'));
      expect(ai, contains('AlfaeqAiService'));
      expect(ai, contains('تأكيد التنفيذ'));
    });

    test('product search matches name, description and barcode', () {
      final search = File('lib/services/unified_search_service.dart').readAsStringSync();
      expect(search, contains("metadata->>barcode.ilike"));
      final tools = File('lib/ai/ai_tools.dart').readAsStringSync();
      expect(tools, contains("metadata->>barcode.ilike"));
      expect(tools, contains(".limit(_max)"));
    });

    test('section page search box filters products', () {
      final home = File('lib/screens/world_home_page.dart').readAsStringSync();
      expect(home, contains('class _WorldSectionPageState'));
      expect(home, contains('onChanged: (v) => setState(() => _query = v)'));
      expect(home, contains("metadata") , reason: 'section filter reads product metadata for barcode');
      expect(home, contains('_productsFuture'));
    });
  });
}
