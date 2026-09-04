import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'app_role.dart';

class RoleService {
  RoleService._();

  static final RoleService instance = RoleService._();
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  Future<AppRole> currentRole() async {
    final user = _auth.currentUser;
    if (user == null) return AppRole.customer;
    final doc = await _db.collection('users').doc(user.uid).get();
    return AppRoleX.fromKey(doc.data()?['role'] as String?);
  }

  Stream<AppRole> roleStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(AppRole.customer);
    return _db.collection('users').doc(user.uid).snapshots().map(
          (doc) => AppRoleX.fromKey(doc.data()?['role'] as String?),
        );
  }

  Future<void> createAccount({
    required String name,
    required String email,
    required String password,
    required AppRole requestedRole,
    String phone = '',
  }) async {
    final role = switch (requestedRole) {
      AppRole.customer => AppRole.customer,
      AppRole.merchant => AppRole.merchant,
      AppRole.driver => AppRole.driver,
      AppRole.manager || AppRole.admin => AppRole.customer,
    };

    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user!;

    // Email remains the fallback verification channel.
    await user.sendEmailVerification();

    await _db.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'name': name.trim(),
      'email': email.trim(),
      'phone': phone.trim(),
      'role': role.key,
      'active': true,
      'approved': false,
      'emailVerified': false,
      'whatsappVerified': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setRole({required String uid, required AppRole role}) async {
    await _db.collection('users').doc(uid).set({
      'role': role.key,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setAccountState({required String uid, required bool active}) async {
    await _db.collection('users').doc(uid).set({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
