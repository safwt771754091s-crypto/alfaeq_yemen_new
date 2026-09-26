import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

/// أدوات ذكاء الفائق — Supabase فقط.
/// لا يوجد fallback إلى Firebase/Firestore؛ كل القراءة والكتابة تمر عبر
/// Supabase Auth + RLS أو RPC المخصص للعمليات الحساسة.
class AlfaeqAiToolRegistry {
  static const int _maxResults = 8;
  final SupabaseClient _client;

  AlfaeqAiToolRegistry({SupabaseClient? client})
      : _client = client ?? SupabaseService.client;

  Future<Map<String, Object?>> execute(
    String name,
    Map<String, Object?> args, {
    required Future<void> Function({
      required String action,
      required String result,
      Map<String, dynamic>? details,
    }) audit,
    bool userConfirmed = false,
  }) async {
    try {
      switch (name) {
        case 'search_catalog':
          return await _searchCatalog(args);
        case 'get_my_orders':
          return await _getMyOrders(args);
        case 'get_my_order':
          return await _getMyOrder(args);
        case 'get_my_account_summary':
          return await _getMyAccountSummary();
        case 'get_security_summary':
          return await _getSecuritySummary(audit: audit);
        case 'get_my_cart':
          return await _getMyCart();
        case 'add_to_cart':
          return await _addToCart(args, userConfirmed: userConfirmed);
        case 'update_cart_item':
          return await _updateCartItem(args, userConfirmed: userConfirmed);
        case 'remove_from_cart':
          return await _removeFromCart(args, userConfirmed: userConfirmed);
        case 'create_order_draft':
          return await _createOrderDraft(args, userConfirmed: userConfirmed);
        default:
          return {'ok': false, 'error': 'الأداة غير مسموحة.'};
      }
    } catch (e) {
      await audit(
        action: 'ai_tool_$name',
        result: 'failed',
        details: {'error': e.toString()},
      );
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
      final rows = await _client
          .from('products')
          .select()
          .eq('status', 'active')
          .order('name')
          .limit(80);
      for (final raw in rows) {
        final d = Map<String, dynamic>.from(raw);
        final name = (d['name'] ?? '').toString();
        final category = (d['section_id'] ?? '').toString();
        if ('$name $category'.toLowerCase().contains(query)) {
          products.add({
            'id': d['id'],
            'name': name,
            'category': category,
            'price': d['price'],
            'currency': d['currency'] ?? 'YER',
            'storeId': d['store_id'],
            'available': d['stock_base'],
          });
        }
        if (products.length >= _maxResults) break;
      }
    }

    if (type == 'stores' || type == 'both') {
      final rows = await _client
          .from('stores')
          .select()
          .inFilter('status', ['approved', 'active'])
          .order('name')
          .limit(80);
      for (final raw in rows) {
        final d = Map<String, dynamic>.from(raw);
        final name = (d['name'] ?? '').toString();
        final category = (d['section_id'] ?? '').toString();
        if ('$name $category'.toLowerCase().contains(query)) {
          stores.add({
            'id': d['id'],
            'name': name,
            'category': category,
            'city': d['address'],
            'active': true,
          });
        }
        if (stores.length >= _maxResults) break;
      }
    }

    return {
      'ok': true,
      'query': query,
      'products': products,
      'stores': stores,
      'resultCount': products.length + stores.length,
    };
  }

  Future<Map<String, Object?>> _getMyOrders(Map<String, Object?> args) async {
    final user = _client.auth.currentUser;
    if (user == null) return {'ok': false, 'error': 'يجب تسجيل الدخول أولاً.'};

    final requestedStatus = (args['status'] ?? 'all').toString();
    final rows = await _client
        .from('orders')
        .select()
        .eq('customer_id', user.id)
        .order('created_at', ascending: false)
        .limit(20);

    final orders = <Map<String, Object?>>[];
    for (final raw in rows) {
      final data = Map<String, dynamic>.from(raw);
      final status = (data['status'] ?? '').toString();
      if (requestedStatus != 'all' && status != requestedStatus) continue;
      orders.add({
        'id': data['id'],
        'status': status,
        'total': data['total'],
        'currency': data['currency'] ?? 'YER',
        'createdAt': _safeDate(data['created_at']),
        'itemCount': data['items'] is List ? (data['items'] as List).length : null,
      });
      if (orders.length >= _maxResults) break;
    }
    return {'ok': true, 'orders': orders, 'resultCount': orders.length};
  }

  Future<Map<String, Object?>> _getMyOrder(Map<String, Object?> args) async {
    final user = _client.auth.currentUser;
    if (user == null) return {'ok': false, 'error': 'يجب تسجيل الدخول أولاً.'};

    final orderId = (args['orderId'] ?? '').toString().trim();
    if (orderId.isEmpty || orderId.length > 128) {
      return {'ok': false, 'error': 'رقم الطلب غير صالح.'};
    }

    final rows = await _client
        .from('orders')
        .select()
        .eq('id', orderId)
        .eq('customer_id', user.id)
        .limit(1);
    if (rows.isEmpty) return {'ok': false, 'error': 'الطلب غير موجود.'};

    final data = Map<String, dynamic>.from(rows.first);
    return {
      'ok': true,
      'order': {
        'id': data['id'],
        'status': data['status'],
        'deliveryStatus': data['delivery_status'],
        'itemCount': data['items'] is List ? (data['items'] as List).length : null,
        'total': data['total'],
        'currency': data['currency'] ?? 'YER',
        'paymentMethod': data['payment_method'],
        'createdAt': _safeDate(data['created_at']),
        'updatedAt': _safeDate(data['updated_at']),
      },
    };
  }

  Future<Map<String, Object?>> _getMyAccountSummary() async {
    final user = _client.auth.currentUser;
    if (user == null) return {'ok': false, 'error': 'يجب تسجيل الدخول أولاً.'};

    final row = await _client
        .from('users')
        .select('uid,name,email,phone,role,admin,owner,developer')
        .eq('uid', user.id)
        .maybeSingle();
    final data = Map<String, dynamic>.from(row ?? const {});
    final metadata = user.userMetadata ?? const <String, dynamic>{};

    return {
      'ok': true,
      'uid': user.id,
      'email': user.email,
      'displayName': data['name'] ?? metadata['full_name'] ?? metadata['name'],
      'phone': data['phone'] ?? user.phone,
      'role': data['role'] ?? 'customer',
      'phoneVerified': user.phone != null,
      'emailVerified': user.emailConfirmedAt != null,
    };
  }

  Future<Map<String, Object?>> _getSecuritySummary({
    required Future<void> Function({
      required String action,
      required String result,
      Map<String, dynamic>? details,
    }) audit,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return {'ok': false, 'error': 'يجب تسجيل الدخول أولاً.'};

    final profile = await _client
        .from('users')
        .select('role,admin,owner,developer')
        .eq('uid', user.id)
        .maybeSingle();
    final data = Map<String, dynamic>.from(profile ?? const {});
    final role = (data['role'] ?? '').toString().toLowerCase();
    final allowed = role == 'owner' ||
        role == 'admin' ||
        role == 'developer' ||
        data['owner'] == true ||
        data['admin'] == true ||
        data['developer'] == true;

    if (!allowed) {
      await audit(
        action: 'ai_tool_get_security_summary',
        result: 'denied',
        details: {'role': role},
      );
      return {'ok': false, 'error': 'هذه الأداة متاحة للمستخدمين المصرح لهم فقط.'};
    }

    final logs = await _client
        .from('audit_logs')
        .select('result,details,created_at')
        .order('created_at', ascending: false)
        .limit(20);
    final failures = logs.where((d) => d['result'] == 'failed').length;
    final warnings = logs.where((d) => d['result'] == 'warning').length;

    await audit(
      action: 'ai_tool_get_security_summary',
      result: 'success',
      details: {'role': role},
    );
    return {
      'ok': true,
      'role': role,
      'recentAuditEntries': logs.length,
      'recentFailures': failures,
      'recentWarnings': warnings,
      'scope': 'ملخص أمني غير حساس فقط.',
    };
  }

  Future<List<Map<String, Object?>>> _cartItems(String uid) async {
    final row = await _client
        .from('carts')
        .select('items,metadata')
        .eq('uid', uid)
        .maybeSingle();
    return _normalizeCartItems(row?['items']);
  }

  Future<Map<String, Object?>> _getMyCart() async {
    final user = _client.auth.currentUser;
    if (user == null) return {'ok': false, 'error': 'يجب تسجيل الدخول أولاً.'};

    final row = await _client
        .from('carts')
        .select('items,metadata')
        .eq('uid', user.id)
        .maybeSingle();
    final items = _normalizeCartItems(row?['items']);
    final metadata = row?['metadata'];
    final currency = metadata is Map ? (metadata['currency'] ?? 'YER') : 'YER';

    return {
      'ok': true,
      'items': items,
      'itemCount': items.length,
      'total': _cartTotal(items),
      'currency': currency,
    };
  }

  Future<void> _saveCart(
    String uid,
    List<Map<String, Object?>> items, {
    String currency = 'YER',
  }) async {
    await _client.from('carts').upsert({
      'uid': uid,
      'owner_id': uid,
      'items': items,
      'metadata': {'currency': currency},
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'uid');
  }

  Future<Map<String, Object?>> _addToCart(
    Map<String, Object?> args, {
    required bool userConfirmed,
  }) async {
    if (!userConfirmed) {
      return {
        'ok': false,
        'error': 'ينتظر تأكيد المستخدم.',
        'permission': 'confirmation_required',
      };
    }

    final user = _client.auth.currentUser;
    if (user == null) return {'ok': false, 'error': 'يجب تسجيل الدخول أولاً.'};

    final productId = (args['productId'] ?? '').toString().trim();
    final quantity = (args['quantity'] as num?)?.toInt() ?? 0;
    if (productId.isEmpty || quantity < 1 || quantity > 100) {
      return {'ok': false, 'error': 'بيانات السلة غير صالحة.'};
    }

    final rows = await _client
        .from('products')
        .select()
        .eq('id', productId)
        .eq('status', 'active')
        .limit(1);
    if (rows.isEmpty) return {'ok': false, 'error': 'المنتج غير موجود أو غير متاح.'};

    final product = Map<String, dynamic>.from(rows.first);
    final stock = (product['stock_base'] as num?)?.toDouble() ?? 0;
    if (stock <= 0) return {'ok': false, 'error': 'المنتج غير متوفر.'};

    final items = await _cartItems(user.id);
    final index = items.indexWhere((e) => e['productId'] == productId);
    final old = index < 0 ? 0 : (items[index]['quantity'] as int? ?? 0);
    final next = old + quantity;
    if (next > 100 || next > stock) {
      return {'ok': false, 'error': 'الكمية المطلوبة تتجاوز المخزون أو الحد المسموح.'};
    }

    final item = <String, Object?>{
      'productId': productId,
      'name': product['name'] ?? 'منتج',
      'quantity': next,
      'price': product['price'],
      'currency': product['currency'] ?? 'YER',
      'storeId': product['store_id'],
    };
    if (index < 0) {
      items.add(item);
    } else {
      items[index] = item;
    }

    await _saveCart(
      user.id,
      items,
      currency: (product['currency'] ?? 'YER').toString(),
    );
    return {
      'ok': true,
      'action': 'added',
      'productId': productId,
      'quantity': next,
      'total': _cartTotal(items),
    };
  }

  Future<Map<String, Object?>> _updateCartItem(
    Map<String, Object?> args, {
    required bool userConfirmed,
  }) async {
    if (!userConfirmed) {
      return {
        'ok': false,
        'error': 'ينتظر تأكيد المستخدم.',
        'permission': 'confirmation_required',
      };
    }

    final user = _client.auth.currentUser;
    if (user == null) return {'ok': false, 'error': 'يجب تسجيل الدخول أولاً.'};

    final productId = (args['productId'] ?? '').toString().trim();
    final quantity = (args['quantity'] as num?)?.toInt() ?? 0;
    if (productId.isEmpty || quantity < 1 || quantity > 100) {
      return {'ok': false, 'error': 'بيانات السلة غير صالحة.'};
    }

    final items = await _cartItems(user.id);
    final index = items.indexWhere((e) => e['productId'] == productId);
    if (index < 0) return {'ok': false, 'error': 'المنتج غير موجود في السلة.'};

    final productRows = await _client
        .from('products')
        .select('stock_base,price,currency,name,store_id')
        .eq('id', productId)
        .limit(1);
    if (productRows.isEmpty) return {'ok': false, 'error': 'المنتج غير موجود.'};
    final stock = (productRows.first['stock_base'] as num?)?.toDouble() ?? 0;
    if (quantity > stock) return {'ok': false, 'error': 'الكمية تتجاوز المخزون المتاح.'};

    items[index]['quantity'] = quantity;
    await _saveCart(
      user.id,
      items,
      currency: (items[index]['currency'] ?? 'YER').toString(),
    );
    return {
      'ok': true,
      'action': 'updated',
      'productId': productId,
      'quantity': quantity,
      'total': _cartTotal(items),
    };
  }

  Future<Map<String, Object?>> _removeFromCart(
    Map<String, Object?> args, {
    required bool userConfirmed,
  }) async {
    if (!userConfirmed) {
      return {
        'ok': false,
        'error': 'ينتظر تأكيد المستخدم.',
        'permission': 'confirmation_required',
      };
    }

    final user = _client.auth.currentUser;
    if (user == null) return {'ok': false, 'error': 'يجب تسجيل الدخول أولاً.'};

    final productId = (args['productId'] ?? '').toString().trim();
    if (productId.isEmpty) return {'ok': false, 'error': 'رقم المنتج غير صالح.'};

    final items = await _cartItems(user.id);
    final before = items.length;
    items.removeWhere((e) => e['productId'] == productId);
    if (items.length == before) {
      return {'ok': false, 'error': 'المنتج غير موجود في السلة.'};
    }

    await _saveCart(user.id, items);
    return {
      'ok': true,
      'action': 'removed',
      'productId': productId,
      'itemCount': items.length,
      'total': _cartTotal(items),
    };
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
      result.add({
        'productId': productId,
        'name': name,
        'quantity': quantity,
        'price': price,
        'currency': value['currency']?.toString() ?? 'YER',
        'storeId': value['storeId']?.toString() ?? '',
      });
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

  Future<Map<String, Object?>> _createOrderDraft(
    Map<String, Object?> args, {
    required bool userConfirmed,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return {'ok': false, 'error': 'يجب تسجيل الدخول أولاً.'};
    if (!userConfirmed) {
      return {
        'ok': false,
        'error': 'ينتظر تأكيد المستخدم.',
        'permission': 'confirmation_required',
      };
    }

    final raw = args['items'];
    final address = (args['address'] ?? '').toString().trim();
    final payment = (args['paymentMethod'] ?? '').toString();
    const methods = {'cash_on_delivery', 'al_kuraimi', 'cash_wallet', 'jeeb_wallet'};
    if (raw is! List || raw.isEmpty || raw.length > 20 || address.isEmpty) {
      return {'ok': false, 'error': 'بيانات الطلب غير مكتملة.'};
    }
    if (!methods.contains(payment)) {
      return {'ok': false, 'error': 'طريقة الدفع غير مدعومة.'};
    }

    final items = raw
        .whereType<Map>()
        .map((item) => <String, dynamic>{
              'product_id': item['productId'] ?? item['product_id'],
              'quantity': item['quantity'],
            })
        .toList();
    if (items.length != raw.length) {
      return {'ok': false, 'error': 'بيانات أحد المنتجات غير صالحة.'};
    }

    // السعر والمخزون النهائيان يحددهما RPC على الخادم، وليس العميل.
    final orderId = await _client.rpc(
      'create_order',
      params: {
        'p_items': items,
        'p_address': address,
        'p_payment_method': payment,
      },
    );

    await _client.from('carts').upsert({
      'uid': user.id,
      'owner_id': user.id,
      'items': <dynamic>[],
      'metadata': <String, dynamic>{},
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'uid');

    return {
      'ok': true,
      'message': 'تم إنشاء الطلب بنجاح.',
      'orderId': orderId.toString(),
      'status': 'pending',
    };
  }

  String? _safeDate(dynamic value) {
    if (value is DateTime) return value.toUtc().toIso8601String();
    return value?.toString();
  }
}
