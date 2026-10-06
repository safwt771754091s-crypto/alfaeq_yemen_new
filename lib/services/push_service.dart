import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'supabase_service.dart';

/// Push notification registration.
///
/// The backend (device_tokens table + push-dispatch function) is provider-ready.
/// Retrieving a native FCM token needs the `firebase_messaging` plugin and a
/// Firebase project, so this service exposes a pluggable [tokenProvider]: once
/// the app registers one (after adding the plugin), the token is stored
/// server-side and notifications fan out automatically. Without a provider it
/// is a safe no-op.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  Future<String?> Function()? tokenProvider;

  static String get platformName {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  /// Obtains the device token (if a provider is registered) and stores it for
  /// the signed-in user. Best-effort: never throws into the UI.
  Future<bool> registerCurrentDevice() async {
    final provider = tokenProvider;
    if (provider == null || !SupabaseService.isInitialized) return false;
    if (SupabaseService.client.auth.currentUser == null) return false;
    try {
      final token = await provider();
      if (token == null || token.isEmpty) return false;
      await registerToken(token);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Stores a device token for the signed-in user via the server RPC.
  Future<void> registerToken(String token, {String? platform}) async {
    await SupabaseService.client.rpc('register_device_token', params: {
      'p_token': token,
      'p_platform': platform ?? platformName,
    });
  }
}
