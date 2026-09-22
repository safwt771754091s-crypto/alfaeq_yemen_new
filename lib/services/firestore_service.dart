import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Compatibility data layer.
///
/// Firebase remains the fallback/backup while Supabase becomes the primary
/// read path for catalog and platform data. Authentication is migrated later.
class FirestoreService {
  final FirebaseFirestore db;
  final SupabaseClient supabase;
  final bool preferSupabase;

  FirestoreService({
    FirebaseFirestore? firestore,
    SupabaseClient? client,
    this.preferSupabase = true,
  })  : db = firestore ?? FirebaseFirestore.instance,
        supabase = client ?? Supabase.instance.client;

  Stream<QuerySnapshot<Map<String, dynamic>>> activeStores(String sectionId) {
    if (!preferSupabase) {
      return db.collection('stores').where('sectionId', isEqualTo: sectionId).where('status', isEqualTo: 'approved').snapshots();
    }
    // Supabase realtime will be introduced after authentication/RLS policies
    // are mapped. Until then, Firebase remains the live stream fallback.
    return db.collection('stores').where('sectionId', isEqualTo: sectionId).where('status', isEqualTo: 'approved').snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> activeProducts(String storeId) {
    if (!preferSupabase) {
      return db.collection('products').where('storeId', isEqualTo: storeId).where('status', isEqualTo: 'active').snapshots();
    }
    return db.collection('products').where('storeId', isEqualTo: storeId).where('status', isEqualTo: 'active').snapshots();
  }

  Future<String> createOrder({
    required String customerId,
    required List<Map<String, dynamic>> items,
    required String address,
    required String paymentMethod,
  }) async {
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

    if (preferSupabase) {
      final response = await supabase.from('orders').insert({
        'id': _id(),
        'customer_id': customerId,
        'merchant_ids': merchantIds.toList(),
        'status': 'pending',
        'delivery_status': 'awaiting_assignment',
        'address': address,
        'payment_method': paymentMethod,
        'items': items,
      }).select('id').single();
      return response['id'] as String;
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
    if (preferSupabase) {
      await supabase.from('orders').update({
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

  String _id() => DateTime.now().microsecondsSinceEpoch.toString();
}
