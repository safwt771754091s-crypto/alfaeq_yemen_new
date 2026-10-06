import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Customer-facing profile operations: avatar, name/phone, password, email.
class ProfileService {
  ProfileService();

  SupabaseClient get _db => SupabaseService.client;
  User? get _user => _db.auth.currentUser;

  static const _avatarBucket = 'media';

  /// Current profile row merged with auth metadata so the UI always has data.
  Future<Map<String, dynamic>> load() async {
    final user = _user;
    if (user == null) return const {};
    Map<String, dynamic> row = const {};
    try {
      final data = await _db
          .from('users')
          .select('uid,email,name,phone,role,metadata,created_at')
          .eq('uid', user.id)
          .maybeSingle();
      if (data != null) row = Map<String, dynamic>.from(data);
    } catch (_) {}
    final meta = user.userMetadata ?? const <String, dynamic>{};
    return {
      ...row,
      'uid': user.id,
      'email': user.email,
      'name': (row['name'] ?? meta['full_name'] ?? meta['name'] ?? '').toString(),
      'phone': (row['phone'] ?? user.phone ?? '').toString(),
      'avatar_url': (row['metadata'] is Map
              ? (row['metadata'] as Map)['avatar_url']
              : null) ??
          meta['avatar_url'],
      'created_at': row['created_at'] ?? user.createdAt,
    };
  }

  /// Uploads an avatar to `media/<uid>/avatar.<ext>` and returns its public URL.
  Future<String> uploadAvatar(Uint8List bytes, String extension) async {
    final user = _user;
    if (user == null) throw StateError('يجب تسجيل الدخول أولاً.');
    final ext = extension.replaceAll('.', '').toLowerCase();
    final safeExt = ext.isEmpty ? 'jpg' : ext;
    final path = '${user.id}/avatar.$safeExt';
    await _db.storage.from(_avatarBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
        );
    // Cache-bust so the new avatar shows immediately after replacement.
    final url = _db.storage.from(_avatarBucket).getPublicUrl(path);
    return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> updateProfile({
    String? name,
    String? phone,
    String? avatarUrl,
  }) async {
    final user = _user;
    if (user == null) throw StateError('يجب تسجيل الدخول أولاً.');

    final patch = <String, dynamic>{
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (name != null) patch['name'] = name.trim();
    if (phone != null) patch['phone'] = phone.trim();

    final meta = <String, dynamic>{...?user.userMetadata};
    if (name != null) meta['full_name'] = name.trim();
    if (avatarUrl != null) meta['avatar_url'] = avatarUrl;

    await _db.from('users').upsert({
      'uid': user.id,
      'email': user.email,
      ...patch,
      'metadata': meta,
    }, onConflict: 'uid');

    await _db.auth.updateUser(UserAttributes(data: {
      if (name != null) 'full_name': name.trim(),
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    }));
  }

  /// Changes the password after verifying the current one.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _user;
    if (user == null || user.email == null) {
      throw StateError('يجب تسجيل الدخول أولاً.');
    }
    // Re-authenticate to confirm the current password is correct.
    await _db.auth.signInWithPassword(
      email: user.email!,
      password: currentPassword,
    );
    await _db.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<void> changeEmail(String newEmail) async {
    await _db.auth.updateUser(UserAttributes(email: newEmail.trim()));
  }

  /// Order count and wallet balance for the profile header stats.
  Future<Map<String, dynamic>> stats() async {
    final user = _user;
    if (user == null) return const {'orders': 0, 'balance': 0};
    var orders = 0;
    num balance = 0;
    try {
      final rows = await _db
          .from('orders')
          .select('id')
          .eq('customer_id', user.id);
      orders = (rows as List).length;
    } catch (_) {}
    try {
      final wallet = await _db
          .from('wallets')
          .select('available_balance')
          .eq('uid', user.id)
          .maybeSingle();
      balance = (wallet?['available_balance'] as num?) ?? 0;
    } catch (_) {}
    return {'orders': orders, 'balance': balance};
  }
}
