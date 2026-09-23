import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class AuthUser {
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoURL;
  const AuthUser({required this.uid, this.email, this.displayName, this.photoURL});
  factory AuthUser.fromSupabase(User user) => AuthUser(
    uid: user.id,
    email: user.email,
    displayName: (user.userMetadata?['full_name'] ?? user.userMetadata?['name'])?.toString(),
    photoURL: user.userMetadata?['avatar_url']?.toString(),
  );
}

class AuthService {
  const AuthService();
  SupabaseClient get _client => SupabaseService.client;
  AuthUser? get currentUser {
    final u = _client.auth.currentUser;
    return u == null ? null : AuthUser.fromSupabase(u);
  }
  Stream<AuthUser?> get authStateChanges => _client.auth.onAuthStateChange.map(
    (event) => event.session?.user == null ? null : AuthUser.fromSupabase(event.session!.user),
  );

  Future<AuthUser> signIn({required String email, required String password}) async {
    final response = await _client.auth.signInWithPassword(email: email.trim(), password: password);
    final user = response.user;
    if (user == null) throw StateError('تعذر تسجيل الدخول.');
    await _ensureProfile(user, provider: 'password');
    return AuthUser.fromSupabase(user);
  }

  Future<AuthUser?> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'io.supabase.alfaeqyemen://login-callback/',
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
    return currentUser;
  }

  Future<void> sendPasswordReset({required String email}) async {
    await _client.auth.resetPasswordForEmail(email.trim());
  }

  Future<AuthUser> register({
    required String name,
    required String email,
    required String password,
    dynamic location,
    String locationSource = 'device',
  }) async {
    final response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'full_name': name.trim(), 'name': name.trim(), 'role': 'customer'},
    );
    final user = response.user;
    if (user == null) throw StateError('تعذر إنشاء الحساب.');
    await _ensureProfile(user, provider: 'password', name: name.trim(), location: location, locationSource: locationSource);
    return AuthUser.fromSupabase(user);
  }

  Future<void> _ensureProfile(
    User user, {
    required String provider,
    String? name,
    dynamic location,
    String locationSource = 'device',
  }) async {
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final row = <String, dynamic>{
      'uid': user.id,
      'email': user.email,
      'name': name ?? metadata['full_name'] ?? metadata['name'] ?? '',
      'role': metadata['role'] ?? 'customer',
      'provider': provider,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (location != null) {
      row['location_source'] = locationSource;
      row['location_updated_at'] = DateTime.now().toUtc().toIso8601String();
    }
    await _client.from('users').upsert(row, onConflict: 'uid');
    await _recordLoginEvent(user, provider: provider);
  }

  Future<void> _recordLoginEvent(User user, {required String provider, String action = 'login'}) async {
    try {
      await _client.from('login_events').insert({
        'uid': user.id,
        'email': user.email,
        'provider': provider,
        'action': action,
        'login_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  Future<void> bootstrapPrimaryAdminIfEligible() async {
    final user = _client.auth.currentUser;
    if (user == null || user.email?.trim().toLowerCase() != 'albyysks@gmail.com') return;
    try {
      await _client.rpc('bootstrap_primary_admin');
    } catch (_) {}
  }

  Future<void> saveUserLocation({required dynamic location, String source = 'device'}) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('يجب تسجيل الدخول.');
    await _client.from('users').upsert({
      'uid': user.id,
      'location_source': source,
      'location_updated_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'uid');
  }

  Future<bool> hasRequiredLocation() async => false;

  Future<void> startPresence() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      await _client.from('users').update({
        'is_online': true,
        'last_seen': DateTime.now().toUtc().toIso8601String(),
      }).eq('uid', user.id);
    } catch (_) {}
  }

  Future<void> stopPresence() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      await _client.from('users').update({
        'is_online': false,
        'last_seen': DateTime.now().toUtc().toIso8601String(),
      }).eq('uid', user.id);
    } catch (_) {}
  }

  Future<void> signOut() async {
    await stopPresence();
    await _client.auth.signOut();
  }

  Future<Map<String, dynamic>> claims({bool forceRefresh = true}) async {
    final user = _client.auth.currentUser;
    if (user == null) return const {};
    final row = await _client.from('users').select('role,admin,owner,developer,access_level').eq('uid', user.id).maybeSingle();
    return row == null ? const {} : Map<String, dynamic>.from(row);
  }

  Future<String> role() async {
    final user = _client.auth.currentUser;
    if (user == null) return 'guest';
    final c = await claims();
    return (c['role'] ?? 'customer').toString();
  }

  Future<bool> hasAdminClaim() async {
    final c = await claims();
    return c['admin'] == true || c['role'] == 'admin' || c['role'] == 'owner';
  }
  Future<bool> hasOwnerClaim() async {
    final c = await claims();
    return c['owner'] == true || c['role'] == 'owner';
  }
  Future<bool> isDeveloper() async {
    final c = await claims();
    return c['developer'] == true || c['role'] == 'developer';
  }
  Future<bool> canOpenDeveloperCenter() async {
    final c = await claims();
    return c['developer'] == true || c['admin'] == true || c['owner'] == true ||
        ['developer', 'admin', 'owner'].contains(c['role']);
  }
}
