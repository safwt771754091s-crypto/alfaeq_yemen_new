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

    test('merchant orders are scoped by merchantIds and status changes are audited', () {
      final orders = File('lib/screens/merchant_orders_page.dart').readAsStringSync();
      final service = File('lib/services/firestore_service.dart').readAsStringSync();
      final rules = File('firestore.rules').readAsStringSync();
      expect(orders, contains("where('merchantIds', arrayContains: user.uid)"));
      expect(orders, contains("collection('auditLogs')"));
      expect(orders, contains('merchant_order_status_'));
      expect(service, contains("'merchantIds': merchantIds.toList()"));
      expect(rules, contains("request.auth.uid in resource.data.merchantIds"));
      expect(rules, contains("request.resource.data.merchantIds == resource.data.merchantIds"));
    });

    test('driver center is role-gated and delivery transitions preserve assignment', () {
      final driver = File('lib/screens/driver_center_page.dart').readAsStringSync();
      final gate = File('lib/screens/auth_gate.dart').readAsStringSync();
      final rules = File('firestore.rules').readAsStringSync();
      expect(driver, contains("role == 'driver'"));
      expect(driver, contains("'currentLocation': GeoPoint"));
      expect(driver, contains("where('driverId', isEqualTo: user.uid)"));
      expect(driver, contains("status == 'assigned'"));
      expect(driver, contains("status == 'delivered'"));
      expect(gate, contains("role == 'driver'"));
      expect(gate, contains('DriverCenterPage()'));
      expect(rules, contains('match /drivers/{uid}'));
      expect(rules, contains("request.resource.data.approved == resource.data.approved"));
      expect(rules, contains("request.resource.data.diff(resource.data).affectedKeys().hasOnly(['isOnline', 'currentLocation', 'lastSeenAt', 'updatedAt', 'activeOrderCount'])"));
      expect(rules, contains("resource.data.driverId == request.auth.uid"));
    });

    test('smart dispatch is distance/load scored and audited', () {
      final service = File('lib/services/dispatch_service.dart').readAsStringSync();
      final center = File('lib/screens/dispatch_center_page.dart').readAsStringSync();
      final rules = File('firestore.rules').readAsStringSync();
      expect(service, contains('distanceKm'));
      expect(service, contains('activeOrderCount'));
      expect(service, contains('dispatchScore'));
      expect(service, contains("'smart_dispatch_assign'"));
      expect(center, contains("where('deliveryStatus', isEqualTo: 'awaiting_assignment')"));
      expect(center, contains('assignBestDriver'));
      expect(center, contains("'deliveryLocation': GeoPoint"));
      expect(rules, contains("function driver()"));
      expect(rules, contains("resource.data.driverId == request.auth.uid"));
    });

    test('location onboarding requires a valid map/device location and legacy profile repair', () {
      final auth = File('lib/services/auth_service.dart').readAsStringSync();
      final gate = File('lib/screens/auth_gate.dart').readAsStringSync();
      final onboarding = File('lib/screens/location_required_page.dart').readAsStringSync();
      final login = File('lib/screens/login_page.dart').readAsStringSync();
      final merchant = File('lib/screens/merchant_center_page.dart').readAsStringSync();
      final rules = File('firestore.rules').readAsStringSync();
      expect(auth, contains('required GeoPoint location'));
      expect(auth, contains('hasRequiredLocation'));
      expect(auth, contains('saveUserLocation'));
      expect(auth, contains('SetOptions(merge: true)'));
      expect(auth, contains("'location': location"));
      expect(auth, contains("'uid': user.uid"));
      expect(gate, contains('hasRequiredLocation()'));
      expect(gate, contains('LocationRequiredPage'));
      expect(gate, contains('setState(() {})'));
      expect(onboarding, contains('LocationPickerPage'));
      expect(onboarding, contains('LocationService.requireCurrentPosition'));
      expect(login, contains('LocationPickerPage'));
      expect(login, contains('_pendingLocation'));
      expect(merchant, contains('LocationService.requireCurrentPosition'));
      expect(merchant, contains("'location': location"));
      expect(rules, contains('function validLocation'));
      expect(rules, contains('validLocation(request.resource.data)'));
      expect(rules, contains("request.resource.data.location is latlng"));
      expect(rules, contains("request.resource.data.get('uid', request.auth.uid) == request.auth.uid"));
      expect(rules, contains("request.resource.data.get('role', resource.data.get('role', 'customer')) == resource.data.get('role', 'customer')"));
    });

    test('order flow prevents forged delivery state and enforces sequential transitions', () {
      final rules = File('firestore.rules').readAsStringSync();
      final service = File('lib/services/firestore_service.dart').readAsStringSync();
      final merchant = File('lib/screens/merchant_orders_page.dart').readAsStringSync();
      final driver = File('lib/screens/driver_center_page.dart').readAsStringSync();
      expect(rules, contains("request.resource.data.status == 'pending'"));
      expect(rules, contains("request.resource.data.deliveryStatus == 'awaiting_assignment'"));
      expect(rules, contains("!('driverId' in request.resource.data)"));
      expect(rules, contains("!('deliveredAt' in request.resource.data)"));
      expect(rules, contains("function validMerchantStatusTransition()"));
      expect(rules, contains("function validDeliveryTransition()"));
      expect(rules, contains("request.resource.data.diff(resource.data).affectedKeys().hasOnly(['status', 'updatedAt'])"));
      expect(rules, contains("request.resource.data.deliveryStatus in ['assigned', 'picked_up', 'out_for_delivery', 'delivered', 'failed']"));
      expect(service, contains("'deliveryStatus': 'awaiting_assignment'"));
      expect(service, contains("'merchantIds': merchantIds.toList()"));
      expect(merchant, contains("onStatus(doc, 'accepted')"));
      expect(merchant, contains("onStatus(doc, 'preparing')"));
      expect(merchant, contains("onStatus(doc, 'ready_for_pickup')"));
      expect(driver, contains("onStatus(doc, 'picked_up')"));
      expect(driver, contains("onStatus(doc, 'out_for_delivery')"));
      expect(driver, contains("onStatus(doc, 'delivered')"));
    });
  });
}
