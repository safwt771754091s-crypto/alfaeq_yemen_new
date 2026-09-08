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

    test('AI service uses limited-use App Check tokens', () {
      final source = File('lib/ai/ai_service.dart').readAsStringSync();

      expect(source, contains('FirebaseAI.googleAI'));
      expect(source, contains('useLimitedUseAppCheckTokens: true'));
      expect(source, contains('_executeThroughGateway'));
      expect(source, contains('ai_action_waiting_confirmation'));
    });

    test('Firestore rules keep audit logs append-only and user-owned data scoped', () {
      final rules = File('firestore.rules').readAsStringSync();

      expect(rules, contains('match /auditLogs/{id}'));
      expect(rules, contains('allow update, delete: if false;'));
      expect(rules, contains('request.resource.data.actorUid == request.auth.uid'));
      expect(rules, contains('match /carts/{uid}'));
      expect(rules, contains('request.resource.data.ownerId == request.auth.uid'));
      expect(rules, contains('request.resource.data.customerId == request.auth.uid'));
    });

    test('merchant onboarding starts pending and approval is staff-gated with audit logging', () {
      final merchant = File('lib/screens/merchant_center_page.dart').readAsStringSync();
      final approval = File('lib/screens/merchant_approval_page.dart').readAsStringSync();
      final rules = File('firestore.rules').readAsStringSync();

      expect(merchant, contains("'status': 'pending'"));
      expect(merchant, contains("'ownerId': user.uid"));
      expect(approval, contains('Future<bool> _isStaff()'));
      expect(approval, contains("where('status', isEqualTo: 'pending')"));
      expect(approval, contains("'reviewedBy': user.uid"));
      expect(approval, contains("collection('auditLogs')"));
      expect(approval, contains("'source': 'admin_merchant_approval'"));
      expect(rules, contains("(merchant() && request.resource.data.ownerId == request.auth.uid)"));
      expect(rules, contains('allow update: if staff()'));
    });
  });
}
