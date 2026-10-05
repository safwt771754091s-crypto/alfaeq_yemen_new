import '../core/app_sections.dart';
import 'supabase_service.dart';

class SearchResults {
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> stores;
  final List<AppSection> sections;
  const SearchResults({this.products = const [], this.stores = const [], this.sections = const []});

  bool get isEmpty => products.isEmpty && stores.isEmpty && sections.isEmpty;
}

/// WeChat-style unified search across products, stores, and platform sections.
class UnifiedSearchService {
  const UnifiedSearchService();

  Future<SearchResults> search(String query, {int limit = 30}) async {
    final q = _sanitize(query);
    if (q.isEmpty) return const SearchResults();

    final sections = appSections
        .where((s) => s.title.contains(q) || s.subtitle.contains(q) || s.id.contains(q.toLowerCase()))
        .toList();

    var products = <Map<String, dynamic>>[];
    var stores = <Map<String, dynamic>>[];

    if (SupabaseService.isInitialized) {
      final db = SupabaseService.client;
      try {
        final rows = await db
            .from('products')
            .select()
            .eq('status', 'active')
            .or('name.ilike.%$q%,description.ilike.%$q%,metadata->>barcode.ilike.%$q%')
            .order('name')
            .limit(limit);
        products = rows.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {
        products = const [];
      }
      try {
        final rows = await db
            .from('stores')
            .select('id,owner_id,name,address,section_id,status,phone')
            .inFilter('status', ['approved', 'active'])
            .or('name.ilike.%$q%,address.ilike.%$q%')
            .order('name')
            .limit(limit);
        stores = rows.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {
        stores = const [];
      }
    }

    return SearchResults(products: products, stores: stores, sections: sections);
  }

  /// PostgREST `or()` splits on commas and treats parentheses as grouping, so
  /// strip those (and wildcards) to keep the filter well-formed.
  String _sanitize(String query) => query
      .trim()
      .replaceAll(RegExp(r'[,()%*]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
