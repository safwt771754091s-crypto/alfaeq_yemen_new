import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

/// Supabase-backed catalog readiness/import facade.
///
/// The catalog lives in the `products` table. An optional `platform-api` edge
/// function can report readiness, but it is not deployed on every environment;
/// probing it on startup produced CORS console errors. We therefore read the
/// table directly and only fall back to the function when the table is empty.
class SuperAlfaeqCatalogImporter {
  const SuperAlfaeqCatalogImporter();

  Future<bool> isReady() async {
    if (!SupabaseService.isInitialized) return false;
    try {
      final rows = await SupabaseService.client.from('products').select('id').limit(1);
      if (rows.isNotEmpty) return true;
    } catch (_) {
      return false;
    }
    return _remoteReady();
  }

  Future<int> importIfNeeded({void Function(int done, int total)? onProgress}) async {
    if (!SupabaseService.isInitialized) return 0;
    try {
      final rows = await SupabaseService.client.from('products').select('id').limit(1);
      final active = rows.length;
      onProgress?.call(active, active);
      return active;
    } on FunctionException {
      return 0;
    } catch (_) {
      return 0;
    }
  }

  /// Best-effort probe of the optional catalog edge function. Any failure
  /// (including a missing deployment) is treated as "not ready".
  Future<bool> _remoteReady() async {
    try {
      final result = await SupabaseService.client.functions.invoke(
        'platform-api',
        body: const {'action': 'catalog_ready'},
      );
      final data = Map<String, dynamic>.from(result.data as Map);
      return data['ok'] == true && data['ready'] == true;
    } catch (_) {
      return false;
    }
  }
}
