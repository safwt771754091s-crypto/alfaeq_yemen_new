import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore db;
  FirestoreService({FirebaseFirestore? firestore}) : db = firestore ?? FirebaseFirestore.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>> activeStores(String sectionId) {
    return db.collection('stores').where('sectionId', isEqualTo: sectionId).where('status', isEqualTo: 'approved').snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> activeProducts(String storeId) {
    return db.collection('products').where('storeId', isEqualTo: storeId).where('status', isEqualTo: 'active').snapshots();
  }

  Future<DocumentReference<Map<String, dynamic>>> createOrder({
    required String customerId,
    required List<Map<String, dynamic>> items,
    required String address,
    required String paymentMethod,
  }) {
    return db.collection('orders').add({
      'customerId': customerId,
      'items': items,
      'address': address,
      'paymentMethod': paymentMethod,
      'status': 'pending',
      'deliveryStatus': 'awaiting_assignment',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> order(String orderId) => db.collection('orders').doc(orderId).snapshots();

  Future<void> updateDelivery(String orderId, String status, {GeoPoint? location}) {
    return db.collection('orders').doc(orderId).update({
      'deliveryStatus': status,
      if (location != null) 'deliveryLocation': location,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
