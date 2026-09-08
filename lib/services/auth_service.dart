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

  Future<UserCredential> register({
    required String name,
    required String email,
    required String password,
    required GeoPoint location,
    String locationSource = 'device',
  }) async {
    final credential = await auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
    final user = credential.user!;
    await user.updateDisplayName(name.trim());
    try {
      await db.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'name': name.trim(),
        'email': user.email,
        'role': 'customer',
        'location': location,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'locationSource': locationSource,
        'locationUpdatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      await user.delete();
      rethrow;
    }
    await user.reload();
    return credential;
  }

  Future<void> saveUserLocation({required GeoPoint location, String source = 'device'}) async {
    final user = auth.currentUser;
    if (user == null) throw StateError('User is not signed in.');
    await db.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'location': location,
      'latitude': location.latitude,
      'longitude': location.longitude,
      'locationSource': source,
      'locationUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> hasRequiredLocation() async {
    final user = auth.currentUser;
    if (user == null) return false;
    final snap = await db.collection('users').doc(user.uid).get();
    final data = snap.data();
    final location = data?['location'];
    return location is GeoPoint &&
        (data?['latitude'] is num) &&
        (data?['longitude'] is num);
  }

  Future<void> signOut() => auth.signOut();

  Future<Map<String, dynamic>> claims({bool forceRefresh = true}) async {
    final user = auth.currentUser;
    if (user == null) return const {};
    final token = await user.getIdTokenResult(forceRefresh);
    return Map<String, dynamic>.from(token.claims ?? const {});
  }

  Future<String> role() async {
    final user = auth.currentUser;
    if (user == null) return 'guest';
    final tokenClaims = await claims();
    final claimRole = tokenClaims['role'];
    if (claimRole is String && claimRole.isNotEmpty) return claimRole;
    if (tokenClaims['admin'] == true) return 'admin';
    final snap = await db.collection('users').doc(user.uid).get();
    return (snap.data()?['role'] as String?) ?? 'customer';
  }

  Future<bool> hasAdminClaim() async {
    final tokenClaims = await claims();
    return tokenClaims['admin'] == true || tokenClaims['role'] == 'admin' || tokenClaims['role'] == 'owner';
  }

  Future<bool> hasOwnerClaim() async {
    final tokenClaims = await claims();
    return tokenClaims['owner'] == true || tokenClaims['role'] == 'owner';
  }

  Future<bool> isDeveloper() async {
    final tokenClaims = await claims();
    if (tokenClaims['role'] == 'developer') return true;
    final user = auth.currentUser;
    if (user == null) return false;
    final snap = await db.collection('users').doc(user.uid).get();
    return snap.data()?['role'] == 'developer';
  }

  Future<bool> canOpenDeveloperCenter() async {
    final tokenClaims = await claims();
    return tokenClaims['owner'] == true ||
        tokenClaims['admin'] == true ||
        tokenClaims['role'] == 'owner' ||
        tokenClaims['role'] == 'admin' ||
        tokenClaims['role'] == 'developer';
  }
}
