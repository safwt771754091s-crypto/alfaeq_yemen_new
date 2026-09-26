import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

/// Legacy filename retained for source compatibility; all operations are
/// backed exclusively by Supabase.
class SupabaseDataService {
  final SupabaseClient supabase;
  SupabaseDataService({SupabaseClient? client, bool preferSupabase = true})
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
    final normalized = items.map((item) => {
      'product_id': item['productId'] ?? item['product_id'],
      'quantity': item['quantity'],
    }).toList();
    final id = await supabase.rpc('create_order', params: {
      'p_items': normalized,
      'p_address': address,
      'p_payment_method': paymentMethod,
      'p_latitude': latitude,
      'p_longitude': longitude,
    });
    return id.toString();
  }

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
