import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth auth;
  final FirebaseFirestore db;

  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : auth = auth ?? FirebaseAuth.instance,
        db = firestore ?? FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => auth.authStateChanges();

  Future<UserCredential> signIn({required String email, required String password}) {
    return auth.signInWithEmailAndPassword(email: email.trim(), password: password);
  }

  Future<void> sendPasswordReset({required String email}) {
    return auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<UserCredential> register({required String name, required String email, required String password}) async {
    final credential = await auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
    final user = credential.user!;
    await user.updateDisplayName(name.trim());
    await db.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'name': name.trim(),
      'email': user.email,
      'role': 'customer',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await user.reload();
    return credential;
  }

  Future<void> signOut() => auth.signOut();

  Future<String> role() async {
    final user = auth.currentUser;
    if (user == null) return 'guest';
    final snap = await db.collection('users').doc(user.uid).get();
    return (snap.data()?['role'] as String?) ?? 'customer';
  }

  Future<bool> hasAdminClaim() async {
    final user = auth.currentUser;
    if (user == null) return false;
    final token = await user.getIdTokenResult(true);
    return token.claims?['admin'] == true;
  }
}
