import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth auth;
  final FirebaseFirestore db;
  final FirebaseFunctions functions;
  Timer? _presenceTimer;

  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : auth = auth ?? FirebaseAuth.instance,
        db = firestore ?? FirebaseFirestore.instance,
        functions = functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  Stream<User?> get authStateChanges => auth.authStateChanges();

  Future<UserCredential> signIn({required String email, required String password}) {
    return auth.signInWithEmailAndPassword(email: email.trim(), password: password);
  }

  Future<UserCredential?> signInWithGoogle() async {
    UserCredential credential;
    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      provider.setCustomParameters({'prompt': 'select_account'});
      credential = await auth.signInWithPopup(provider);
    } else {
      final google = GoogleSignIn();
      final account = await google.signIn();
      if (account == null) return null;
      final googleAuth = await account.authentication;
      final oauth = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      credential = await auth.signInWithCredential(oauth);
    }

    final user = credential.user;
    if (user == null) return credential;
    await _ensureUserProfile(user);
    await startPresence();
    if ((user.email ?? '').trim().toLowerCase() == 'albyysks@gmail.com') {
      await bootstrapPrimaryAdminIfEligible();
    }
    return credential;
  }

  Future<void> _ensureUserProfile(User user) async {
    final ref = db.collection('users').doc(user.uid);
    final snapshot = await ref.get();
    if (snapshot.exists) {
      await ref.set({
        'email': user.email,
        'name': (user.displayName ?? '').trim(),
        'photoUrl': user.photoURL,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }
    await ref.set({
      'uid': user.uid,
      'name': (user.displayName ?? '').trim(),
      'email': user.email,
      'photoUrl': user.photoURL,
      'role': 'customer',
      'provider': 'google',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> bootstrapPrimaryAdminIfEligible() async {
    final user = auth.currentUser;
    if (user == null) return;
    final email = (user.email ?? '').trim().toLowerCase();
    if (email != 'albyysks@gmail.com') return;
    final callable = functions.httpsCallable('bootstrapPrimaryAdmin');
    await callable.call(<String, dynamic>{});
    await user.getIdToken(true);
    await user.reload();
  }

  Future<void> sendPasswordReset({required String email}) {
    return auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<UserCredential> register({
    required String name,
    required String email,
    required String password,
    GeoPoint? location,
    String locationSource = 'device',
  }) async {
    final credential = await auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
    final user = credential.user!;
    await user.updateDisplayName(name.trim());
    try {
      final profile = <String, dynamic>{
        'uid': user.uid,
        'name': name.trim(),
        'email': user.email,
        'role': 'customer',
        'provider': 'password',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (location != null) {
        profile.addAll({
          'location': location,
          'latitude': location.latitude,
          'longitude': location.longitude,
          'locationSource': locationSource,
          'locationUpdatedAt': FieldValue.serverTimestamp(),
        });
      }
      await db.collection('users').doc(user.uid).set(profile);
    } catch (_) {
      await user.delete();
      rethrow;
    }
    await user.reload();
    await startPresence();
    return credential;
  }

  Future<void> saveUserLocation({required GeoPoint location, String source = 'device'}) async {
    final user = auth.currentUser;
    if (user == null) throw StateError('User is not signed in.');
    final ref = db.collection('users').doc(user.uid);
    final snapshot = await ref.get();
    final existing = snapshot.data();
    final update = <String, dynamic>{
      'uid': user.uid,
      'location': location,
      'latitude': location.latitude,
      'longitude': location.longitude,
      'locationSource': source,
      'locationUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'name': (user.displayName ?? '').trim(),
      'email': user.email,
    };
    if (!snapshot.exists) {
      update['role'] = 'customer';
      update['createdAt'] = FieldValue.serverTimestamp();
    } else if (existing?['role'] == null) {
      update['role'] = 'customer';
    }
    await ref.set(update, SetOptions(merge: true));
  }

  Future<bool> hasRequiredLocation() async {
    final user = auth.currentUser;
    if (user == null) return false;
    final snap = await db.collection('users').doc(user.uid).get();
    final data = snap.data();
    final location = data?['location'];
    return location is GeoPoint && (data?['latitude'] is num) && (data?['longitude'] is num);
  }

  Future<void> startPresence() async {
    final user = auth.currentUser;
    if (user == null) return;
    _presenceTimer?.cancel();
    await _touchPresence(user);
    _presenceTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final current = auth.currentUser;
      if (current != null) _touchPresence(current);
    });
  }

  Future<void> _touchPresence(User user) async {
    try {
      await db.collection('users').doc(user.uid).set({
        'lastSeen': FieldValue.serverTimestamp(),
        'isOnline': true,
      }, SetOptions(merge: true));
    } catch (_) {
      // Presence must never prevent login or navigation.
    }
  }

  Future<void> stopPresence() async {
    _presenceTimer?.cancel();
    _presenceTimer = null;
    final user = auth.currentUser;
    if (user == null) return;
    try {
      await db.collection('users').doc(user.uid).set({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> signOut() async {
    await stopPresence();
    await auth.signOut();
  }

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
    if (tokenClaims['developer'] == true || tokenClaims['role'] == 'developer') return true;
    final user = auth.currentUser;
    if (user == null) return false;
    final snap = await db.collection('users').doc(user.uid).get();
    return snap.data()?['developer'] == true || snap.data()?['role'] == 'developer';
  }

  Future<bool> canOpenDeveloperCenter() async {
    final tokenClaims = await claims();
    return tokenClaims['owner'] == true ||
        tokenClaims['admin'] == true ||
        tokenClaims['developer'] == true ||
        tokenClaims['role'] == 'owner' ||
        tokenClaims['role'] == 'admin' ||
        tokenClaims['role'] == 'developer';
  }
}
