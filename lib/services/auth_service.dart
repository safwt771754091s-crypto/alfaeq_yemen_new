import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class AuthService {
  GoTrueClient get auth => SupabaseService.client.auth;

  User? get currentUser => auth.currentUser;

  Stream<User?> get authStateChanges =>
      auth.onAuthStateChange.map((event) => event.session?.user);

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final response = await auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    final user = response.user;
    if (user != null) {
      await _ensureUserProfile(user, provider: 'password');
      await _recordLoginEvent(user, provider: 'password');
      await startPresence();
    }
    return response;
  }

  Future<AuthResponse?> signInWithGoogle() async {
    final google = GoogleSignIn();
    final account = await google.signIn();
    if (account == null) return null;

    final googleAuth = await account.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('لم يتم استلام رمز Google المطلوب لتسجيل الدخول.');
    }

    final response = await auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: googleAuth.accessToken,
    );
    final user = response.user;
    if (user == null) return response;

    await _ensureUserProfile(user, provider: 'google');
    await _recordLoginEvent(user, provider: 'google');
    await startPresence();
    return response;
  }

  Future<void> _ensureUserProfile(
    User user, {
    required String provider,
  }) async {
    final existing = await SupabaseService.client
        .from('users')
        .select('uid')
        .eq('uid', user.id)
        .maybeSingle();

    final metadata = <String, dynamic>{
      ...user.userMetadata ?? const <String, dynamic>{},
      'provider': provider,
    };

    await SupabaseService.client.from('users').upsert({
      'uid': user.id,
      'email': user.email,
      'name': (user.userMetadata?['full_name'] ??
              user.userMetadata?['name'] ??
              '')
          .toString()
          .trim(),
      if (existing == null) 'role': 'customer',
      'metadata': metadata,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'uid');
  }

  Future<void> bootstrapPrimaryAdminIfEligible() async {
    // Administrative roles are provisioned server-side in Supabase.
    // Never grant owner/admin privileges from a client-side email check.
  }

  Future<void> sendPasswordReset({required String email}) async {
    await auth.resetPasswordForEmail(email.trim());
  }

  Future<AuthResponse> register({
    required String name,
    required String email,
    required String password,
    dynamic location,
    String locationSource = 'device',
  }) async {
    final response = await auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'name': name.trim(),
        'full_name': name.trim(),
      },
    );

    final user = response.user;
    if (user == null) {
      throw StateError('تعذر إنشاء حساب المستخدم.');
    }

    final profile = <String, dynamic>{
      'uid': user.id,
      'name': name.trim(),
      'email': user.email,
      'role': 'customer',
      'metadata': {
        'provider': 'password',
        'location_source': locationSource,
      },
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (location is Map) {
      profile['location'] = Map<String, dynamic>.from(location);
    }

    try {
      await SupabaseService.client.from('users').upsert(
            profile,
            onConflict: 'uid',
          );
    } catch (_) {
      // The auth account is authoritative; profile creation can be retried
      // after email confirmation or on the next authenticated request.
    }

    await _recordLoginEvent(user, provider: 'password', action: 'register');
    return response;
  }

  Future<void> saveUserLocation({
    required double latitude,
    required double longitude,
    String source = 'device',
  }) async {
    final user = currentUser;
    if (user == null) throw StateError('User is not signed in.');

    await SupabaseService.client.from('users').upsert({
      'uid': user.id,
      'email': user.email,
      'location': {
        'latitude': latitude,
        'longitude': longitude,
        'source': source,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'uid');
  }

  Future<bool> hasRequiredLocation() async {
    final user = currentUser;
    if (user == null) return false;

    final row = await SupabaseService.client
        .from('users')
        .select('location')
        .eq('uid', user.id)
        .maybeSingle();
    final location = row?['location'];
    return location is Map &&
        location['latitude'] is num &&
        location['longitude'] is num;
  }

  Future<void> startPresence() async {
    final user = currentUser;
    if (user == null) return;
    await _touchPresence(user);
  }

  Future<void> _touchPresence(User user) async {
    try {
      await SupabaseService.client.from('users').update({
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('uid', user.id);
    } catch (_) {}
  }

  Future<void> stopPresence() async {}

  Future<void> signOut() async {
    try {
      await auth.signOut();
    } finally {
      if (!kIsWeb) {
        try {
          await GoogleSignIn().signOut().timeout(const Duration(seconds: 3));
        } catch (_) {}
      }
    }
  }

  Future<Map<String, dynamic>> claims({bool forceRefresh = true}) async {
    final user = currentUser;
    if (user == null) return const {};

    final profile = await SupabaseService.client
        .from('users')
        .select('role,admin,owner,developer,access_level,metadata')
        .eq('uid', user.id)
        .maybeSingle();

    return {
      'sub': user.id,
      'email': user.email,
      ...Map<String, dynamic>.from(profile ?? const {}),
    };
  }

  Future<String> role() async {
    final user = currentUser;
    if (user == null) return 'guest';

    final row = await SupabaseService.client
        .from('users')
        .select('role,admin,owner,developer')
        .eq('uid', user.id)
        .maybeSingle();

    final data = row ?? const <String, dynamic>{};
    final role = (data['role'] ?? '').toString();
    if (role.isNotEmpty) return role;
    if (data['owner'] == true) return 'owner';
    if (data['admin'] == true) return 'admin';
    if (data['developer'] == true) return 'developer';
    return 'customer';
  }

  Future<bool> hasAdminClaim() async {
    final c = await claims();
    return c['admin'] == true ||
        c['owner'] == true ||
        c['role'] == 'admin' ||
        c['role'] == 'owner';
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
    return c['owner'] == true ||
        c['admin'] == true ||
        c['developer'] == true ||
        c['role'] == 'owner' ||
        c['role'] == 'admin' ||
        c['role'] == 'developer';
  }

  Future<void> _recordLoginEvent(
    User user, {
    required String provider,
    String action = 'login',
  }) async {
    try {
      await SupabaseService.client.from('login_events').insert({
        'uid': user.id,
        'email': user.email,
        'provider': provider,
        'action': action,
        'login_at': DateTime.now().toUtc().toIso8601String(),
        'metadata': {
          'platform': defaultTargetPlatform.name,
        },
      });
    } catch (e) {
      debugPrint('Supabase login event failed: $e');
    }
  }
}
