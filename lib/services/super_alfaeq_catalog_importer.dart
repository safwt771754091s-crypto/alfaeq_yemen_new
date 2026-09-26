import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

/// Supabase-backed catalog readiness/import facade.
class SuperAlfaeqCatalogImporter {
  const SuperAlfaeqCatalogImporter();

  Future<bool> isReady() async {
    if (!SupabaseService.isInitialized) return false;
    try {
      final result = await SupabaseService.client.functions.invoke(
        'platform-api',
        body: const {'action': 'catalog_ready'},
      );
      final data = Map<String, dynamic>.from(result.data as Map);
      return data['ok'] == true && data['ready'] == true;
    } catch (_) {
      try {
        final rows = await SupabaseService.client.from('products').select('id').limit(1);
        return rows.isNotEmpty;
      } catch (_) {
        return false;
      }
    }
  }

  Future<int> importIfNeeded({void Function(int done, int total)? onProgress}) async {
    if (!SupabaseService.isInitialized) return 0;
    try {
      final result = await SupabaseService.client.functions.invoke(
        'platform-api',
        body: const {'action': 'catalog_ready'},
      );
      final data = Map<String, dynamic>.from(result.data as Map);
      final active = (data['active'] as num?)?.toInt() ?? 0;
      onProgress?.call(active, active);
      return active;
    } on FunctionException {
      return 0;
    }
  }
}
