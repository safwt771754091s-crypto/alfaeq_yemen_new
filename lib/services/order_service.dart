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
  }) async {
    final normalized = _normalize(items);
    final id = await supabase.rpc('create_order', params: {
      'p_items': normalized,
      'p_address': address,
      'p_payment_method': paymentMethod,
      'p_latitude': latitude,
      'p_longitude': longitude,
    });
    return id.toString();
  }

  /// Wallet balance for the signed-in user (creates the wallet on first use).
  Future<num> walletBalance({String currency = 'YER'}) async =>
      (await walletInfo(currency: currency)).balance;

  /// Wallet balance plus its actual currency. Wallets are keyed by user, so the
  /// returned currency is authoritative and may differ from the requested one.
  Future<({num balance, String currency})> walletInfo({String currency = 'YER'}) async {
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
    String currency = 'YER',
    double? latitude,
    double? longitude,
  }) async {
    final normalized = _normalize(items);
    final id = await supabase.rpc('create_order_paid', params: {
      'p_items': normalized,
      'p_address': address,
      'p_idempotency_key': idempotencyKey,
      'p_currency': currency,
      'p_latitude': latitude,
      'p_longitude': longitude,
    });
    return id.toString();
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
