import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Alfaeq Yemen security architecture', () {
    test('AI permission gateway remains default-deny and confirmation-gated', () {
      final source = File('lib/ai/ai_permission_gateway.dart').readAsStringSync();
      expect(source, contains('Default-deny'));
      expect(source, contains("if (policy == null) return AiPermissionDecision.denied"));
      expect(source, contains('requiresConfirmation'));
      expect(source, contains('userConfirmed'));
      expect(source, contains("AiActionLevel.reversible"));
      expect(source, contains("'create_order_draft'"));
    });

    test('AI service uses the Supabase to Unsloth gateway and confirmation flow', () {
      final source = File('lib/ai/ai_service.dart').readAsStringSync();
      final gateway = File('lib/services/unsloth_ai_service.dart').readAsStringSync();
      expect(source, contains("import '../services/unsloth_ai_service.dart';"));
      expect(source, contains('final UnslothAiService _ai;'));
      expect(source, contains('_ai.chatCompletion('));
      expect(source, contains('requiresConfirmation'));
      expect(source, contains('_pendingAction'));
      expect(source, contains('confirmPendingAction'));
      expect(source, isNot(contains('FirebaseAI.googleAI')));
      expect(source, isNot(contains('useLimitedUseAppCheckTokens')));
      expect(gateway, contains('ai-gateway'));
      expect(gateway, contains('Supabase'));
    });

    test('merchant portal is role-gated before opening merchant controls', () {
      final portal = File('lib/screens/merchant_portal_page.dart').readAsStringSync();
      expect(portal, contains("import '../services/auth_service.dart';"));
      expect(portal, contains("role == 'merchant'"));
      expect(portal, contains("role == 'admin'"));
      expect(portal, contains("role == 'owner'"));
      expect(portal, contains("role == 'developer'"));
      expect(portal, contains('const MerchantCenterPage()'));
      expect(portal, contains('const MerchantOrdersPage()'));
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

    test('order flow prevents forged merchant state through the Supabase RPC', () {
      final migration = File('supabase/migrations/20260923160000_stage4_merchant_order_transitions.sql').readAsStringSync();
      final merchant = File('lib/screens/merchant_orders_page.dart').readAsStringSync();
      expect(migration, contains('security definer'));
      expect(migration, contains('uid := auth.uid()::text'));
      expect(migration, contains("raise exception 'not authenticated'"));
      expect(migration, contains("raise exception 'not authorized'"));
      expect(migration, contains("raise exception 'invalid merchant order transition'"));
      expect(merchant, contains("rpc('transition_order'"));
    });
  });
}
