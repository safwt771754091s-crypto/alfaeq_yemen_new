import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore db;

  FirestoreService({FirebaseFirestore? firestore})
      : db = firestore ?? FirebaseFirestore.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>> activeStores(String sectionId) {
    return db
        .collection('stores')
        .where('sectionId', isEqualTo: sectionId)
        .where('status', isEqualTo: 'approved')
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> activeProducts(String storeId) {
    return db
        .collection('products')
        .where('storeId', isEqualTo: storeId)
        .where('status', isEqualTo: 'active')
        .snapshots();
  }

  Future<DocumentReference<Map<String, dynamic>>> createOrder({
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

    return db.collection('orders').add({
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
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> order(String orderId) =>
      db.collection('orders').doc(orderId).snapshots();

  Future<void> updateDelivery(String orderId, String status, {GeoPoint? location}) {
    final data = <String, dynamic>{
      'deliveryStatus': status,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (location != null) {
      data['deliveryLocation'] = location;
    }
    return db.collection('orders').doc(orderId).update(data);
  }
}
