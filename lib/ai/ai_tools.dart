import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Allow-listed, read-only tools for Alfaeq AI.
/// Sensitive mutations must stay behind a trusted server-side permission layer.
class AlfaeqAiToolRegistry {
  static const int _maxResults = 8;
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  AlfaeqAiToolRegistry({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  List<FunctionDeclaration> get declarations => [
        FunctionDeclaration(
          'search_catalog',
          'Search Alfaeq Yemen products and stores. Read-only; never return passwords, payment secrets, private addresses, or credentials.',
          parameters: {
            'query': Schema.string(description: 'Arabic or English search phrase.'),
            'type': Schema.enumString(
              enumValues: ['products', 'stores', 'both'],
              description: 'Search target.',
            ),
          },
          optionalParameters: const ['type'],
        ),
        FunctionDeclaration(
          'get_my_orders',
          'Read the signed-in user own orders only. Never access another user order.',
          parameters: {
            'status': Schema.enumString(
              enumValues: ['all', 'pending', 'confirmed', 'preparing', 'shipped', 'delivered', 'cancelled'],
              description: 'Optional order status.',
            ),
          },
          optionalParameters: const ['status'],
        ),
        FunctionDeclaration(
          'get_my_account_summary',
          'Read a safe summary of the signed-in account. Never return authentication secrets.',
          parameters: {},
        ),
        FunctionDeclaration(
          'get_security_summary',
          'For owner/admin/developer only: return non-sensitive security aggregates. Read-only.',
          parameters: {},
        ),
      ];

  Future<Map<String, Object?>> execute(
    String name,
    Map<String, Object?> args, {
    required Future<void> Function({required String action, required String result, Map<String, dynamic>? details}) audit,
  }) async {
    try {
      switch (name) {
        case 'search_catalog': return _searchCatalog(args);
        case 'get_my_orders': return _getMyOrders(args);
        case 'get_my_account_summary': return _getMyAccountSummary();
        case 'get_security_summary': return _getSecuritySummary(audit: audit);
        default: return {'ok': false, 'error': 'الأداة غير مسموحة.'};
      }
    } catch (e) {
      await audit(action: 'ai_tool_$name', result: 'failed', details: {'error': e.toString()});
      return {'ok': false, 'error': 'تعذر تنفيذ الأداة بأمان.'};
    }
  }

  Future<Map<String, Object?>> _searchCatalog(Map<String, Object?> args) async {
    final query = (args['query'] ?? '').toString().trim().toLowerCase();
    final type = (args['type'] ?? 'both').toString();
    if (query.isEmpty) return {'ok': false, 'error': 'يجب تحديد عبارة بحث.'};
    if (query.length > 80) return {'ok': false, 'error': 'عبارة البحث طويلة جداً.'};
    final products = <Map<String, Object?>>[];
    final stores = <Map<String, Object?>>[];

    if (type == 'products' || type == 'both') {
      final snap = await _db.collection('products').limit(80).get();
      for (final doc in snap.docs) {
        final data = doc.data();
        final name = (data['name'] ?? data['title'] ?? '').toString();
        final category = (data['category'] ?? '').toString();
        if ('$name $category'.toLowerCase().contains(query)) {
          products.add({'id': doc.id, 'name': name, 'category': category, 'price': data['price'], 'currency': data['currency'] ?? 'YER', 'storeId': data['storeId'] ?? data['storeID'] ?? data['ownerId'], 'available': data['available'] ?? data['isAvailable']});
        }
        if (products.length >= _maxResults) break;
      }
    }
    if (type == 'stores' || type == 'both') {
      final snap = await _db.collection('stores').limit(80).get();
      for (final doc in snap.docs) {
        final data = doc.data();
        final name = (data['name'] ?? data['title'] ?? '').toString();
        final category = (data['category'] ?? '').toString();
        if ('$name $category'.toLowerCase().contains(query)) {
          stores.add({'id': doc.id, 'name': name, 'category': category, 'city': data['city'] ?? data['locationCity'], 'active': data['active'] ?? data['isActive']});
        }
        if (stores.length >= _maxResults) break;
      }
    }
    return {'ok': true, 'query': query, 'products': products, 'stores': stores, 'resultCount': products.length + stores.length};
  }

  Future<Map<String, Object?>> _getMyOrders(Map<String, Object?> args) async {
    final user = _auth.currentUser;
    if (user == null) return {'ok': false, 'error': 'يجب تسجيل الدخول أولاً.'};
    final requestedStatus = (args['status'] ?? 'all').toString();
    final snap = await _db.collection('orders').where('userId', isEqualTo: user.uid).limit(20).get();
    final orders = <Map<String, Object?>>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final status = (data['status'] ?? '').toString();
      if (requestedStatus != 'all' && status != requestedStatus) continue;
      orders.add({'id': doc.id, 'status': status, 'total': data['total'], 'currency': data['currency'] ?? 'YER', 'createdAt': _safeDate(data['createdAt']), 'storeId': data['storeId'], 'itemCount': data['items'] is List ? (data['items'] as List).length : null});
      if (orders.length >= _maxResults) break;
    }
    return {'ok': true, 'orders': orders, 'resultCount': orders.length};
  }

  Future<Map<String, Object?>> _getMyAccountSummary() async {
    final user = _auth.currentUser;
    if (user == null) return {'ok': false, 'error': 'يجب تسجيل الدخول أولاً.'};
    final snap = await _db.collection('users').doc(user.uid).get();
    final data = snap.data() ?? <String, dynamic>{};
    return {'ok': true, 'uid': user.uid, 'email': user.email, 'displayName': data['name'] ?? data['displayName'] ?? user.displayName, 'role': data['role'], 'phoneVerified': user.phoneNumber != null, 'emailVerified': user.emailVerified};
  }

  Future<Map<String, Object?>> _getSecuritySummary({required Future<void> Function({required String action, required String result, Map<String, dynamic>? details}) audit}) async {
    final user = _auth.currentUser;
    if (user == null) return {'ok': false, 'error': 'يجب تسجيل الدخول أولاً.'};
    final userSnap = await _db.collection('users').doc(user.uid).get();
    final role = (userSnap.data()?['role'] ?? '').toString().toLowerCase();
    const allowedRoles = {'owner', 'admin', 'developer'};
    if (!allowedRoles.contains(role)) {
      await audit(action: 'ai_tool_get_security_summary', result: 'denied', details: {'role': role});
      return {'ok': false, 'error': 'هذه الأداة متاحة للمستخدمين المصرح لهم فقط.'};
    }
    final logs = await _db.collection('auditLogs').orderBy('createdAt', descending: true).limit(20).get();
    final failures = logs.docs.where((d) => d.data()['result'] == 'failed').length;
    final warnings = logs.docs.where((d) => d.data()['severity'] == 'warning' || d.data()['result'] == 'warning').length;
    await audit(action: 'ai_tool_get_security_summary', result: 'success', details: {'role': role});
    return {'ok': true, 'role': role, 'recentAuditEntries': logs.docs.length, 'recentFailures': failures, 'recentWarnings': warnings, 'scope': 'ملخص أمني غير حساس فقط.'};
  }

  String? _safeDate(dynamic value) {
    if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
    if (value is DateTime) return value.toUtc().toIso8601String();
    return value?.toString();
  }
}
