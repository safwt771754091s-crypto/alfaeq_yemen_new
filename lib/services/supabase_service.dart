import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Central Supabase bootstrap and configuration.
///
/// The publishable key is supplied at build time; no service-role key is ever
/// embedded in the Flutter application.
class SupabaseService {
  static bool _initialized = false;

  static bool get isInitialized => _initialized;

  static const projectUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://esvljorjykzgrpnrxnma.supabase.co',
  );
  // Supabase publishable keys are designed for public clients. Keep this as a\n  // build-safe fallback so the web app cannot silently disable its real backend\n  // when CI does not inject SUPABASE_PUBLISHABLE_KEY.\n  static const publishableKey = String.fromEnvironment(\n    'SUPABASE_PUBLISHABLE_KEY',\n    defaultValue: 'sb_publishable_xJfLBgrqWM8yEa3FM9qfig_FwnfTKue',\n  );

  static Future<void> initialize() async {
    if (publishableKey.isEmpty) return;
    await Supabase.initialize(
      url: projectUrl,
      publishableKey: publishableKey,
      debug: false,
      accessToken: () async => FirebaseAuth.instance.currentUser?.getIdToken(),
    );
    _initialized = true;
  }

  static SupabaseClient get client => Supabase.instance.client;
}
