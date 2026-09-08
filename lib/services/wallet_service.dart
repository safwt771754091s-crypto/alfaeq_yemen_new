import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class WalletService {
  WalletService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get _uid => _auth.currentUser!.uid;

  DocumentReference<Map<String, dynamic>> get _walletRef =>
      _firestore.collection('wallets').doc(_uid);

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchWallet() => _walletRef.snapshots();

  Future<void> initializeZeroWallet() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('يجب تسجيل الدخول أولاً');
    final snapshot = await _walletRef.get();
    if (snapshot.exists) return;
    await _walletRef.set({
      'uid': user.uid,
      'currency': 'YER',
      'availableBalance': 0,
      'reservedBalance': 0,
      'status': 'active',
      'version': 1,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchTransactions() => _firestore
      .collection('walletTransactions')
      .where('uid', isEqualTo: _uid)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots();
}
