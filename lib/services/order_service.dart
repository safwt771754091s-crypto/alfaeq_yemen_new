import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

/// Supabase-backed order and catalog operations.
class OrderService {
  final SupabaseClient supabase;
  OrderService({SupabaseClient? client, bool preferSupabase = true})
      : supabase = client ?? SupabaseService.client;

  Future<List<Map<String, dynamic>>> activeStores(String sectionId) async {
    final rows = await supabase.from('stores').select().eq('section_id', sectionId).eq('status', 'approved').order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> activeProducts(String storeId) async {
    final rows = await supabase.from('products').select().eq('store_id', storeId).eq('status', 'active').order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<String> createOrder({
    required String customerId,
    required List<Map<String, dynamic>> items,
    required String address,
    required String paymentMethod,
    double? latitude,
    double? longitude,
    String displayCurrency = 'YER',
  }) async {
    final normalized = _normalize(items);
    final id = await supabase.rpc('create_order', params: {
      'p_items': normalized,
      'p_address': address,
      'p_payment_method': paymentMethod,
      'p_latitude': latitude,
      'p_longitude': longitude,
      'p_display_currency': displayCurrency,
    });
    return id.toString();
  }

  /// Wallet balance for the signed-in user (creates the wallet on first use).
  Future<num> walletBalance({String currency = 'USD'}) async =>
      (await walletInfo(currency: currency)).balance;

  /// Wallet balance plus its actual currency. Wallets are keyed by user, so the
  /// returned currency is authoritative and may differ from the requested one.
  Future<({num balance, String currency})> walletInfo({String currency = 'USD'}) async {
    final row = await supabase.rpc('ensure_my_wallet', params: {
      'p_currency': currency,
      'p_account_type': 'customer',
    });
    if (row is Map) {
      final balance = row['available_balance'];
      return (
        balance: balance is num ? balance : 0,
        currency: (row['currency'] ?? currency).toString(),
      );
    }
    return (balance: 0, currency: currency);
  }

  /// Pays for an order from the in-app wallet. The order and the wallet debit
  /// happen in one server-side transaction, so a failed payment (e.g. an
  /// insufficient balance) leaves no order behind. [idempotencyKey] makes
  /// retries safe.
  Future<String> createPaidOrder({
    required List<Map<String, dynamic>> items,
    required String address,
    required String idempotencyKey,
    String currency = 'USD',
    double? latitude,
    double? longitude,
    String displayCurrency = 'YER',
  }) async {
    final normalized = _normalize(items);
    final id = await supabase.rpc('create_order_paid', params: {
      'p_items': normalized,
      'p_address': address,
      'p_idempotency_key': idempotencyKey,
      'p_currency': currency,
      'p_latitude': latitude,
      'p_longitude': longitude,
      'p_display_currency': displayCurrency,
    });
    return id.toString();
  }

  /// Creates an order to be paid through an online provider (no wallet debit).
  /// The returned order id is then passed to [createPaymentIntent].
  Future<String> createPendingOrder({
    required List<Map<String, dynamic>> items,
    required String address,
    String provider = 'manual',
    double? latitude,
    double? longitude,
    String displayCurrency = 'YER',
  }) async {
    final normalized = _normalize(items);
    final id = await supabase.rpc('create_pending_order', params: {
      'p_items': normalized,
      'p_address': address,
      'p_provider': provider,
      'p_display_currency': displayCurrency,
      'p_latitude': latitude,
      'p_longitude': longitude,
    });
    return id.toString();
  }

  /// Asks the payment gateway which online providers are actually configured.
  Future<List<String>> paymentProviders() async {
    final res = await supabase.functions.invoke('payment-gateway', body: {'action': 'providers'});
    final data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : const <String, dynamic>{};
    final list = data['enabledProviders'];
    return list is List ? list.map((e) => e.toString()).toList() : const <String>[];
  }

  /// Creates a payment intent for an order with an online provider.
  Future<Map<String, dynamic>> createPaymentIntent({required String orderId, String? provider}) async {
    final res = await supabase.functions.invoke('payment-gateway', body: {
      'action': 'create_intent',
      'orderId': orderId,
      if (provider != null) 'provider': provider,
    });
    final data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : const <String, dynamic>{};
    if (data['ok'] != true) throw StateError(data['error']?.toString() ?? 'payment_intent_failed');
    return data;
  }

  /// Confirms an intent with the provider and, when the PSP reports success,
  /// marks the order paid server-side.
  Future<bool> confirmPayment({required String orderId, required String providerRef, String? provider}) async {
    final res = await supabase.functions.invoke('payment-gateway', body: {
      'action': 'confirm',
      'orderId': orderId,
      'providerRef': providerRef,
      if (provider != null) 'provider': provider,
    });
    final data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : const <String, dynamic>{};
    return data['status'] == 'paid';
  }

  /// Submits a bank/e-wallet transfer receipt for staff review.
  Future<void> submitLocalPayment({
    required String orderId,
    required String reference,
    required String receiptUrl,
    String? note,
  }) async {
    await supabase.rpc('submit_local_payment', params: {
      'p_order_id': orderId,
      'p_reference': reference,
      'p_receipt_url': receiptUrl,
      'p_note': note,
    });
  }

  /// Staff: approve (mark paid) or reject a submitted local transfer.
  Future<bool> approveLocalPayment({required String orderId, required bool approve, String? note}) async {
    final res = await supabase.rpc('approve_local_payment', params: {
      'p_order_id': orderId,
      'p_approve': approve,
      'p_note': note,
    });
    return res == true;
  }

  /// Orders awaiting a local-transfer review (staff view).
  Future<List<Map<String, dynamic>>> pendingLocalPayments() async {
    final rows = await supabase
        .from('orders')
        .select('id, customer_id, total, currency, created_at, metadata')
        .eq('metadata->>payment_status', 'awaiting_review')
        .order('created_at', ascending: false)
        .limit(100);
    return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  List<Map<String, dynamic>> _normalize(List<Map<String, dynamic>> items) => items
      .map((item) => {
            'product_id': item['productId'] ?? item['product_id'],
            'quantity': item['quantity'],
          })
      .toList();

  Future<void> clearCart(String uid) async {
    await supabase.from('carts').upsert({
      'uid': uid,
      'owner_id': uid,
      'items': <dynamic>[],
      'metadata': <String, dynamic>{},
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'uid');
  }

  Stream<List<Map<String, dynamic>>> supabaseMyOrders(String uid) =>
      supabase.from('orders').stream(primaryKey: ['id']).eq('customer_id', uid).order('created_at', ascending: false).limit(50);

  Future<Map<String, dynamic>?> supabaseOrder(String orderId) async {
    final rows = await supabase.from('orders').select().eq('id', orderId).limit(1);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  /// Customer-side cancellation. The server enforces that only an unpaid,
  /// non-terminal order can be cancelled and releases any reserved inventory.
  Future<void> cancelMyOrder(String orderId) async {
    await supabase.rpc('transition_order', params: {'p_order_id': orderId, 'p_status': 'cancelled'});
  }

  Stream<List<Map<String, dynamic>>> order(String orderId) =>
      supabase.from('orders').stream(primaryKey: ['id']).eq('id', orderId).limit(1);

  Future<void> updateDelivery(String orderId, String status, {Map<String, dynamic>? location}) async {
    await supabase.from('orders').update({
      'delivery_status': status,
      if (location != null) 'driver_location': location,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', orderId);
  }
}
