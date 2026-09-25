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

    test('merchant orders are scoped by Supabase store ownership and server-side transitions', () {
      final orders = File('lib/screens/merchant_orders_page.dart').readAsStringSync();
      final migration = File('supabase/migrations/20260923160000_stage4_merchant_order_transitions.sql').readAsStringSync();
      expect(orders, contains("from('stores').select('id').eq('owner_id',uid)"));
      expect(orders, contains("overlaps('merchant_ids',ids)"));
      expect(orders, contains("rpc('transition_order'"));
      expect(orders, contains("p_status':status"));
      expect(migration, contains('s.owner_id = uid'));
      expect(migration, contains('s.id = o.merchant_id or s.id = any(o.merchant_ids)'));
      expect(migration, contains("raise exception 'not authorized'"));
      expect(migration, contains("raise exception 'invalid merchant order transition'"));
      expect(migration, contains("current_status='pending' and p_status in ('accepted','cancelled')"));
      expect(migration, contains("current_status='accepted' and p_status in ('preparing','cancelled')"));
      expect(migration, contains("current_status='preparing' and p_status='ready_for_pickup'"));
    });

    test('driver center is role-gated and delivery transitions preserve assignment', () {
      final driver = File('lib/screens/driver_center_page.dart').readAsStringSync();
      final gate = File('lib/screens/auth_gate.dart').readAsStringSync();
      final rules = File('firestore.rules').readAsStringSync();
      expect(driver, contains("['driver','admin','owner','developer'].contains(role)"));
      expect(driver, contains("'current_location'"));
      expect(driver, contains("rpc('driver_update_location'"));
      expect(driver, contains("eq('driver_id',user.uid)"));
      expect(driver, contains("status=='assigned'"));
      expect(driver, contains("_setStatus(id,'delivered')"));
      expect(gate, contains("final role = roleSnapshot.data ?? 'customer';"));
      expect(gate, contains("case 'driver':"));
      expect(gate, contains('DriverCenterPage()'));
      expect(rules, contains('match /drivers/{uid}'));
      expect(driver, contains("rpc('driver_update_order'"));
    });

    test('location is optional at signup and requested only by location-dependent features', () {
      final auth = File('lib/services/auth_service.dart').readAsStringSync();
      final gate = File('lib/screens/auth_gate.dart').readAsStringSync();
      final login = File('lib/screens/login_page.dart').readAsStringSync();
      final onboarding = File('lib/screens/location_required_page.dart').readAsStringSync();
      final merchant = File('lib/screens/merchant_center_page.dart').readAsStringSync();
      final rules = File('firestore.rules').readAsStringSync();

      expect(auth, contains('GeoPoint? location'));
      expect(auth, contains('if (location != null)'));
      expect(auth, contains('saveUserLocation'));
      expect(auth, contains('SetOptions(merge: true)'));
      expect(auth, contains("'location': location"));
      expect(gate, isNot(contains('hasRequiredLocation()')));
      expect(gate, isNot(contains('LocationRequiredPage')));
      expect(login, isNot(contains('_pendingLocation')));
      expect(login, isNot(contains('LocationPickerPage')));
      expect(onboarding, contains('LocationPickerPage'));
      expect(onboarding, contains('LocationService.requireCurrentPosition'));
      expect(merchant, contains('LocationService.requireCurrentPosition'));
      expect(merchant, contains("'location': location"));
      expect(rules, contains('function validLocation'));
      expect(rules, contains("!('location' in request.resource.data) || validLocation(request.resource.data)"));
      expect(rules, contains("request.resource.data.get('uid', request.auth.uid) == request.auth.uid"));
      expect(rules, contains("request.resource.data.get('role', resource.data.get('role', 'customer')) == resource.data.get('role', 'customer')"));
    });

    test('order flow prevents forged merchant state through the Supabase RPC', () {
      final migration = File('supabase/migrations/20260923160000_stage4_merchant_order_transitions.sql').readAsStringSync();
      final merchant = File('lib/screens/merchant_orders_page.dart').readAsStringSync();
      expect(migration, contains('security definer'));
      expect(migration, contains("uid := auth.uid()::text"));
      expect(migration, contains("if uid is null then raise exception 'not authenticated'"));
      expect(migration, contains('select exists('));
      expect(migration, contains('s.owner_id = uid'));
      expect(migration, contains("raise exception 'not authorized'"));
      expect(migration, contains("raise exception 'invalid merchant order transition'"));
      expect(migration, contains("p_status in ('accepted','cancelled')"));
      expect(migration, contains("p_status in ('preparing','cancelled')"));
      expect(migration, contains("p_status='ready_for_pickup'"));
      expect(merchant, contains("if(status=='pending')"));
      expect(merchant, contains("if(status=='accepted')"));
      expect(merchant, contains("if(status=='preparing')"));
      expect(merchant, contains("onStatus(order,'cancelled')"));
    });
  });
}
