import 'package:supabase_flutter/supabase_flutter.dart';

/// Central Supabase bootstrap and configuration.
///
/// Supabase is the application backend. Authentication tokens are supplied
/// by Supabase Auth; no Firebase credential is injected into the client.
class SupabaseService {
  static bool _initialized = false;

  static bool get isInitialized => _initialized;

  static const projectUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://esvljorjykzgrpnrxnma.supabase.co',
  );

  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_xJfLBgrqWM8yEa3FM9qfig_FwnfTKue',
  );

  static Future<void> initialize() async {
    if (_initialized || publishableKey.isEmpty) return;
    // Use Supabase's supported platform storage on every target. The previous
    // web-only EmptyLocalStorage override disabled the SDK's normal browser
    // session path and still left PKCE storage on the default implementation.
    // That combination is not appropriate for a production auth client.
    await Supabase.initialize(
      url: projectUrl,
      publishableKey: publishableKey,
      authOptions: const FlutterAuthClientOptions(
        persistSession: true,
      ),
      debug: false,
    );
    _initialized = true;
  }

  static SupabaseClient get client => Supabase.instance.client;
}
