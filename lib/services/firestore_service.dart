import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

/// Compatibility data layer.
///
/// Firebase remains the fallback/backup while Supabase becomes the primary
/// read path for catalog and platform data. Authentication is migrated later.
class FirestoreService {
  final FirebaseFirestore db;
  final SupabaseClient? supabase;
  final bool preferSupabase;

  FirestoreService({
    FirebaseFirestore? firestore,
    SupabaseClient? client,
    this.preferSupabase = false,
  })  : db = firestore ?? FirebaseFirestore.instance,
        supabase = client ?? (SupabaseService.isInitialized ? Supabase.instance.client : null);

  Future<List<Map<String, dynamic>>> activeStores(String sectionId) async {
    if (preferSupabase && supabase != null) {
      try {
        final rows = await supabase!
            .from('stores')
            .select()
            .eq('section_id', sectionId)
            .eq('status', 'approved')
            .order('name');
        return List<Map<String, dynamic>>.from(rows);
      } catch (_) {
        // Firebase remains the read fallback during migration.
      }
    }
    final snap = await db
        .collection('stores')
        .where('sectionId', isEqualTo: sectionId)
        .where('status', isEqualTo: 'approved')
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<List<Map<String, dynamic>>> activeProducts(String storeId) async {
    if (preferSupabase && supabase != null) {
      try {
        final rows = await supabase!
            .from('products')
            .select()
            .eq('store_id', storeId)
            .eq('status', 'active')
            .order('name');
        return List<Map<String, dynamic>>.from(rows);
      } catch (_) {
        // Firebase remains the read fallback during migration.
      }
    }
    final snap = await db
        .collection('products')
        .where('storeId', isEqualTo: storeId)
        .where('status', isEqualTo: 'active')
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<String> createOrder({
    required String customerId,
    required List<Map<String, dynamic>> items,
    required String address,
    required String paymentMethod,
    double? latitude,
    double? longitude,
  }) async {
    if (preferSupabase && supabase != null) {
      final normalizedItems = items.map((item) => {
            'product_id': item['productId'] ?? item['product_id'],
            'quantity': item['quantity'],
          }).toList();

      final orderId = await supabase!.rpc('create_order', params: {
        'p_items': normalizedItems,
        'p_address': address,
        'p_payment_method': paymentMethod,
        'p_latitude': latitude,
        'p_longitude': longitude,
      });
      return orderId as String;
    }

    final merchantIds = <String>{};
    for (final item in items) {
      final merchantId = item['merchantId']?.toString();
      if (merchantId != null && merchantId.isNotEmpty) {
        merchantIds.add(merchantId);
        continue;
      }
      final storeId = item['storeId']?.toString() ?? '';
      if (storeId.isEmpty) continue;
      final store = await db.collection('stores').doc(storeId).get();
      final ownerId = store.data()?['ownerId']?.toString() ?? '';
      if (store.exists && ownerId.isNotEmpty) merchantIds.add(ownerId);
    }

    final ref = await db.collection('orders').add({
      'customerId': customerId,
      'merchantIds': merchantIds.toList(),
      'items': items,
      'address': address,
      'paymentMethod': paymentMethod,
      'status': 'pending',
      'deliveryStatus': 'awaiting_assignment',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> order(String orderId) =>
      db.collection('orders').doc(orderId).snapshots();

  Future<void> updateDelivery(String orderId, String status, {GeoPoint? location}) async {
    if (preferSupabase && supabase != null) {
      await supabase!.from('orders').update({
        'delivery_status': status,
        if (location != null) 'delivery_location': {
          'latitude': location.latitude,
          'longitude': location.longitude,
        },
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', orderId);
      return;
    }
    final data = <String, dynamic>{
      'deliveryStatus': status,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (location != null) data['deliveryLocation'] = location;
    await db.collection('orders').doc(orderId).update(data);
  }
}
