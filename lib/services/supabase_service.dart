import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static bool _initialized = false;
  static bool get isInitialized => _initialized;
  static const projectUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://esvljorjykzgrpnrxnma.supabase.co');
  static const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY', defaultValue: 'sb_publishable_xJfLBgrqWM8yEa3FM9qfig_FwnfTKue');
  static Future<void> initialize() async {
    if (_initialized) return;
    await Supabase.initialize(url: projectUrl, publishableKey: publishableKey, debug: false);
    _initialized = true;
  }
  static SupabaseClient get client => Supabase.instance.client;
}
