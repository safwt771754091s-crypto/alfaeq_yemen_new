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

  Future<String> requestTransfer({required String recipientUid, required num amount}) async {
    _validateAmount(amount);
    final normalizedRecipient = recipientUid.trim();
    if (normalizedRecipient.isEmpty || normalizedRecipient == _uid) {
      throw ArgumentError('المستفيد غير صالح');
    }
    return _createOperation({
      'type': 'transfer',
      'recipientUid': normalizedRecipient,
      'amount': amount.toDouble(),
    });
  }

  Future<String> requestDeposit({required num amount}) async {
    _validateAmount(amount);
    return _createOperation({'type': 'deposit', 'amount': amount.toDouble()});
  }

  Future<String> requestWithdraw({required num amount}) async {
    _validateAmount(amount);
    return _createOperation({'type': 'withdraw', 'amount': amount.toDouble()});
  }

  Future<String> _createOperation(Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('يجب تسجيل الدخول أولاً');
    final ref = _firestore.collection('walletOperations').doc();
    await ref.set({
      ...data,
      'uid': user.uid,
      'status': 'pending',
      'currency': 'YER',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  void _validateAmount(num amount) {
    if (!amount.isFinite || amount <= 0) throw ArgumentError('المبلغ يجب أن يكون أكبر من صفر');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchTransactions() => _firestore
      .collection('walletTransactions')
      .where('uid', isEqualTo: _uid)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots();
}
