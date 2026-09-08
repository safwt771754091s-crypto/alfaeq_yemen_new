import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Allow-listed tools for Alfaeq AI.
/// Sensitive mutations remain behind the permission gateway and trusted
/// backend boundary. Order creation only creates a pending order after
/// explicit user confirmation; it never charges or processes a payment.
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
          'get_my_order',
          'Read one signed-in user order by ID. Access is still enforced by Firestore rules; never access another user order.',
          parameters: {
            'orderId': Schema.string(description: 'Order document ID.'),
          },
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
        FunctionDeclaration(
          'get_my_cart',
          'Read the signed-in user shopping cart and calculate its current snapshot total. Read-only.',
          parameters: {},
        ),
        FunctionDeclaration(
          'add_to_cart',
          'Add an active catalog product to the signed-in user cart. The product name, store and price are read from Firestore, not trusted from AI input.',
          parameters: {
            'productId': Schema.string(description: 'Active product document ID.'),
            'quantity': Schema.integer(description: 'Quantity to add, from 1 to 100.', minimum: 1, maximum: 100),
          },
        ),
        FunctionDeclaration(
          'update_cart_item',
          'Set a cart item quantity for the signed-in user. Use quantity 1-100; use remove_from_cart to delete it.',
          parameters: {
            'productId': Schema.string(description: 'Product document ID already in the cart.'),
            'quantity': Schema.integer(description: 'New quantity from 1 to 100.', minimum: 1, maximum: 100),
          },
        ),
        FunctionDeclaration(
          'remove_from_cart',
          'Remove one product from the signed-in user cart.',
          parameters: {
            'productId': Schema.string(description: 'Product document ID in the cart.'),
          },
        ),
        FunctionDeclaration(
          'create_order_draft',
          'Create a pending order after the user explicitly confirms. Never process payment. Use only the signed-in user as customerId.',
          parameters: {
            'items': Schema.array(
              description: 'Order items. Each item contains productId, name, quantity, and optional price/storeId.',
              minItems: 1,
              maxItems: 20,
              items: Schema.object(
                properties: {
                  'productId': Schema.string(description: 'Product document ID.'),
                  'name': Schema.string(description: 'Product name.'),
                  'quantity': Schema.integer(description: 'Quantity from 1 to 100.', minimum: 1, maximum: 100),
                  'price': Schema.number(description: 'Optional product price snapshot.'),
                  'storeId': Schema.string(description: 'Optional store document ID.'),
                },
                optionalProperties: const ['price', 'storeId'],
              ),
            ),
            'address': Schema.string(description: 'Delivery address supplied by the signed-in user.'),
            'paymentMethod': Schema.enumString(
              enumValues: ['cash_on_delivery', 'al_kuraimi', 'cash_wallet', 'jeeb_wallet'],
              description: 'Selected payment method. Selecting it does not charge the user.',
            ),
          },
        ),
      ];

  Future<Map<String, Object?>> execute(
    String name,
    Map<String, Object?> args, {
    required Future<void> Function({required String action, required String result, Map<String, dynamic>? details}) audit,
    bool userConfirmed = false,
  }) async {
    try {
      switch (name) {
        case 'search_catalog': return await _searchCatalog(args);
        case 'get_my_orders': return await _getMyOrders(args);
        case 'get_my_order': return await _getMyOrder(args);
        case 'get_my_account_summary': return await _getMyAccountSummary();
        case 'get_security_summary': return await _getSecuritySummary(audit: audit);
        case 'get_my_cart': return await _getMyCart();
        case 'add_to_cart': return await _addToCart(args, userConfirmed: userConfirmed);
        case 'update_cart_item': return await _updateCartItem(args, userConfirmed: userConfirmed);
        case 'remove_from_cart': return await _removeFromCart(args, userConfirmed: userConfirmed);
        case 'create_order_draft': return await _createOrderDraft(args, userConfirmed: userConfirmed);
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
      final snap = await _db.collection('products').where('status', isEqualTo: 'active').limit(80).get();
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
      final snap = await _db.collection('stores').where('status', isEqualTo: 'approved').limit(80).get();
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
    final snap = await _db.collection('orders').where('customerId', isEqualTo: user.uid).limit(20).get();
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

  Future<Map<String, Object?>> _getMyOrder(Map<String, Object?> args) async {
    final user = _auth.currentUser;
    if (user == null) return {'ok': false, 'error': 'يجب تسجيل الدخول أولاً.'};
    final orderId = (args['orderId'] ?? '').toString().trim();
    if (orderId.isEmpty || orderId.length > 128) return {'ok': false, 'error': 'رقم الطلب غير صالح.'};
    final doc = await _db.collection('orders').doc(orderId).get();
    if (!doc.exists) return {'ok': false, 'error': 'الطلب غير موجود.'};
    final data = doc.data()!;
    if (data['customerId'] != user.uid) return {'ok': false, 'error': 'لا تملك صلاحية الوصول إلى هذا الطلب.'};
    return {'ok': true, 'order': {'id': doc.id, 'status': data['status'], 'deliveryStatus': data['deliveryStatus'], 'itemCount': data['items'] is List ? (data['items'] as List).length : null, 'total': data['total'], 'currency': data['currency'] ?? 'YER', 'paymentMethod': data['paymentMethod'], 'createdAt': _safeDate(data['createdAt']), 'updatedAt': _safeDate(data['updatedAt'])}};
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

  Future<Map<String, Object?>> _getMyCart() async {
    final user = _auth.currentUser;
    if (user == null) return {'ok': false, 'error': 'يجب تسجيل الدخول أولاً.'};
    final snap = await _db.collection('carts').doc(user.uid).get();
    if (!snap.exists) return {'ok': true, 'items': <Map<String, Object?>>[], 'itemCount': 0, 'total': 0, 'currency': 'YER'};
    final data = snap.data() ?? <String, dynamic>{};
    final items = _normalizeCartItems(data['items']);
    return {'ok': true, 'items': items, 'itemCount': items.length, 'total': _cartTotal(items), 'currency': data['currency'] ?? 'YER', 'updatedAt': _safeDate(data['updatedAt'])};
  }

  Future<Map<String, Object?>> _addToCart(Map<String, Object?> args, {required bool userConfirmed}) async {
    if (!userConfirmed) return {'ok': false, 'error': 'ينتظر تأكيد المستخدم.', 'permission': 'confirmation_required'};
    final user = _auth.currentUser;
    if (user == null) return {'ok': false, 'error': 'يجب تسجيل الدخول أولاً.'};
    final productId = (args['productId'] ?? '').toString().trim();
    final quantity = (args['quantity'] as num?)?.toInt() ?? 0;
    if (productId.isEmpty || productId.length > 128 || quantity < 1 || quantity > 100) return {'ok': false, 'error': 'بيانات السلة غير صالحة.'};

    final productSnap = await _db.collection('products').doc(productId).get();
    if (!productSnap.exists) return {'ok': false, 'error': 'المنتج غير موجود.'};
    final product = productSnap.data()!;
    final status = (product['status'] ?? '').toString().toLowerCase();
    final available = product['available'] ?? product['isAvailable'];
    if (status != 'active' || available == false) return {'ok': false, 'error': 'المنتج غير متاح حالياً.'};
    final price = product['price'];
    if (price is! num || price < 0) return {'ok': false, 'error': 'سعر المنتج غير صالح.'};
    final name = (product['name'] ?? product['title'] ?? '').toString().trim();
    if (name.isEmpty || name.length > 160) return {'ok': false, 'error': 'اسم المنتج غير صالح.'};
    final storeId = (product['storeId'] ?? product['storeID'] ?? product['ownerId'] ?? '').toString();

    final ref = _db.collection('carts').doc(user.uid);
    final current = await ref.get();
    final data = current.data() ?? <String, dynamic>{};
    final items = _normalizeCartItems(data['items']);
    final index = items.indexWhere((item) => item['productId'] == productId);
    final newQuantity = index == -1 ? quantity : ((items[index]['quantity'] as int) + quantity);
    if (newQuantity > 100) return {'ok': false, 'error': 'الحد الأقصى للمنتج في السلة هو 100.'};
    if (index == -1 && items.length >= 20) return {'ok': false, 'error': 'السلة ممتلئة. الحد الأقصى 20 منتجاً مختلفاً.'};
    final item = <String, Object?>{'productId': productId, 'name': name, 'quantity': newQuantity, 'price': price, 'currency': product['currency'] ?? 'YER', 'storeId': storeId};
    if (index == -1) {
      items.add(item);
    } else {
      items[index] = item;
    }
    await ref.set({'ownerId': user.uid, 'items': items, 'currency': product['currency'] ?? 'YER', 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    return {'ok': true, 'action': 'added', 'productId': productId, 'quantity': newQuantity, 'total': _cartTotal(items)};
  }

  Future<Map<String, Object?>> _updateCartItem(Map<String, Object?> args, {required bool userConfirmed}) async {
    if (!userConfirmed) return {'ok': false, 'error': 'ينتظر تأكيد المستخدم.', 'permission': 'confirmation_required'};
    final user = _auth.currentUser;
    if (user == null) return {'ok': false, 'error': 'يجب تسجيل الدخول أولاً.'};
    final productId = (args['productId'] ?? '').toString().trim();
    final quantity = (args['quantity'] as num?)?.toInt() ?? 0;
    if (productId.isEmpty || quantity < 1 || quantity > 100) return {'ok': false, 'error': 'بيانات السلة غير صالحة.'};
    final ref = _db.collection('carts').doc(user.uid);
    final snap = await ref.get();
    final items = _normalizeCartItems(snap.data()?['items']);
    final index = items.indexWhere((item) => item['productId'] == productId);
    if (index == -1) return {'ok': false, 'error': 'المنتج غير موجود في السلة.'};
    items[index]['quantity'] = quantity;
    await ref.set({'ownerId': user.uid, 'items': items, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    return {'ok': true, 'action': 'updated', 'productId': productId, 'quantity': quantity, 'total': _cartTotal(items)};
  }

  Future<Map<String, Object?>> _removeFromCart(Map<String, Object?> args, {required bool userConfirmed}) async {
    if (!userConfirmed) return {'ok': false, 'error': 'ينتظر تأكيد المستخدم.', 'permission': 'confirmation_required'};
    final user = _auth.currentUser;
    if (user == null) return {'ok': false, 'error': 'يجب تسجيل الدخول أولاً.'};
    final productId = (args['productId'] ?? '').toString().trim();
    if (productId.isEmpty) return {'ok': false, 'error': 'رقم المنتج غير صالح.'};
    final ref = _db.collection('carts').doc(user.uid);
    final snap = await ref.get();
    final items = _normalizeCartItems(snap.data()?['items']);
    final before = items.length;
    items.removeWhere((item) => item['productId'] == productId);
    if (items.length == before) return {'ok': false, 'error': 'المنتج غير موجود في السلة.'};
    await ref.set({'ownerId': user.uid, 'items': items, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    return {'ok': true, 'action': 'removed', 'productId': productId, 'itemCount': items.length, 'total': _cartTotal(items)};
  }

  List<Map<String, Object?>> _normalizeCartItems(dynamic raw) {
    if (raw is! List) return <Map<String, Object?>>[];
    final result = <Map<String, Object?>>[];
    for (final value in raw.take(20)) {
      if (value is! Map) continue;
      final productId = value['productId']?.toString() ?? '';
      final name = value['name']?.toString() ?? '';
      final quantity = value['quantity'] is num ? (value['quantity'] as num).toInt() : 0;
      final price = value['price'];
      if (productId.isEmpty || name.isEmpty || quantity < 1 || quantity > 100 || price is! num || price < 0) continue;
      result.add({'productId': productId, 'name': name, 'quantity': quantity, 'price': price, 'currency': value['currency']?.toString() ?? 'YER', 'storeId': value['storeId']?.toString() ?? ''});
    }
    return result;
  }

  num _cartTotal(List<Map<String, Object?>> items) {
    num total = 0;
    for (final item in items) {
      final price = item['price'];
      final quantity = item['quantity'];
      if (price is num && quantity is int) total += price * quantity;
    }
    return total;
  }

  Future<Map<String, Object?>> _createOrderDraft(Map<String, Object?> args, {required bool userConfirmed}) async {
    final user = _auth.currentUser;
    if (user == null) return {'ok': false, 'error': 'يجب تسجيل الدخول أولاً.'};
    if (!userConfirmed) return {'ok': false, 'error': 'ينتظر تأكيد المستخدم.', 'permission': 'confirmation_required'};
    final rawItems = args['items'];
    final address = (args['address'] ?? '').toString().trim();
    final paymentMethod = (args['paymentMethod'] ?? '').toString();
    const methods = {'cash_on_delivery', 'al_kuraimi', 'cash_wallet', 'jeeb_wallet'};
    if (rawItems is! List || rawItems.isEmpty || rawItems.length > 20) return {'ok': false, 'error': 'يجب تحديد من 1 إلى 20 منتجاً.'};
    if (address.isEmpty || address.length > 300) return {'ok': false, 'error': 'عنوان التوصيل غير صالح.'};
    if (!methods.contains(paymentMethod)) return {'ok': false, 'error': 'طريقة الدفع غير مدعومة.'};

    final items = <Map<String, Object?>>[];
    num total = 0;
    for (final raw in rawItems) {
      if (raw is! Map) return {'ok': false, 'error': 'بيانات أحد المنتجات غير صالحة.'};
      final productId = raw['productId']?.toString() ?? '';
      final quantity = raw['quantity'] is num ? (raw['quantity'] as num).toInt() : 0;
      if (productId.isEmpty || quantity < 1 || quantity > 100) return {'ok': false, 'error': 'بيانات منتج غير صالحة.'};
      final productSnap = await _db.collection('products').doc(productId).get();
      if (!productSnap.exists) return {'ok': false, 'error': 'أحد المنتجات لم يعد موجوداً.'};
      final product = productSnap.data()!;
      final status = (product['status'] ?? '').toString().toLowerCase();
      final available = product['available'] ?? product['isAvailable'];
      final price = product['price'];
      final name = (product['name'] ?? product['title'] ?? '').toString().trim();
      if (status != 'active' || available == false || price is! num || price < 0 || name.isEmpty || name.length > 160) return {'ok': false, 'error': 'أحد المنتجات غير متاح أو بيانات سعره غير صالحة.'};
      final itemTotal = price * quantity;
      total += itemTotal;
      items.add({'productId': productId, 'name': name, 'quantity': quantity, 'price': price, 'lineTotal': itemTotal, 'currency': product['currency'] ?? 'YER', 'storeId': product['storeId'] ?? product['storeID'] ?? product['ownerId']});
    }

    final ref = await _db.collection('orders').add({'customerId': user.uid, 'items': items, 'total': total, 'currency': 'YER', 'address': address, 'paymentMethod': paymentMethod, 'status': 'pending', 'deliveryStatus': 'awaiting_assignment', 'source': 'ai_confirmed', 'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()});
    return {'ok': true, 'orderId': ref.id, 'status': 'pending', 'total': total, 'currency': 'YER', 'paymentProcessed': false, 'message': 'تم إنشاء الطلب المعلّق بعد تأكيدك. لم تتم أي عملية دفع.'};
  }

  String? _safeDate(dynamic value) {
    if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
    if (value is DateTime) return value.toUtc().toIso8601String();
    return value?.toString();
  }
}
