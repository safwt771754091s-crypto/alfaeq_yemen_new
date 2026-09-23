import 'supabase_service.dart';

/// Legacy filename retained temporarily for source compatibility.
/// All production data operations now execute against Supabase only.
class FirestoreService {
  final bool preferSupabase;
  const FirestoreService({this.preferSupabase = true});

  Future<List<Map<String, dynamic>>> activeStores(String sectionId) async {
    final rows = await SupabaseService.client.from('stores').select().eq('section_id', sectionId).eq('status', 'approved').order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> activeProducts(String storeId) async {
    final rows = await SupabaseService.client.from('products').select().eq('store_id', storeId).eq('status', 'active').order('name');
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
    if (customerId != SupabaseService.client.auth.currentUser?.id) {
      throw StateError('جلسة المستخدم غير صالحة.');
    }
    final normalizedItems = items.map((item) => {
      'product_id': item['productId'] ?? item['product_id'],
      'quantity': item['quantity'],
    }).toList();
    final result = await SupabaseService.client.rpc('create_order', params: {
      'p_items': normalizedItems,
      'p_address': address,
      'p_payment_method': paymentMethod,
      'p_latitude': latitude,
      'p_longitude': longitude,
    });
    return result.toString();
  }

  Future<void> clearCart(String uid) async {
    if (uid != SupabaseService.client.auth.currentUser?.id) throw StateError('جلسة المستخدم غير صالحة.');
    await SupabaseService.client.from('carts').upsert({
      'uid': uid,
      'owner_id': uid,
      'items': <dynamic>[],
      'metadata': <String, dynamic>{},
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'uid');
  }

  Stream<List<Map<String, dynamic>>> supabaseMyOrders(String uid) =>
      SupabaseService.client.from('orders').stream(primaryKey: ['id']).eq('customer_id', uid).order('created_at', ascending: false).limit(50);

  Stream<List<Map<String, dynamic>>> supabaseOrderStream(String orderId) =>
      SupabaseService.client.from('orders').stream(primaryKey: ['id']).eq('id', orderId).limit(1);

  Future<Map<String, dynamic>?> supabaseOrder(String orderId) async {
    final rows = await SupabaseService.client.from('orders').select().eq('id', orderId).limit(1);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  Future<void> updateDelivery(String orderId, String status, {dynamic location}) async {
    final data = <String, dynamic>{
      'delivery_status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (location != null) {
      final lat = location.latitude;
      final lng = location.longitude;
      data['driver_location'] = {'latitude': lat, 'longitude': lng};
    }
    await SupabaseService.client.from('orders').update(data).eq('id', orderId);
  }
}
