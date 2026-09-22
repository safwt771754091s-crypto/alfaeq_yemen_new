import 'package:supabase_flutter/supabase_flutter.dart';

/// Central Supabase bootstrap and configuration.
///
/// The publishable key is supplied at build time; no service-role key is ever
/// embedded in the Flutter application.
class SupabaseService {
  static const projectUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://esvljorjykzgrpnrxnma.supabase.co',
  );
  static const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static Future<void> initialize() async {
    if (publishableKey.isEmpty) return;
    await Supabase.initialize(
      url: projectUrl,
      anonKey: publishableKey,
      debug: false,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
