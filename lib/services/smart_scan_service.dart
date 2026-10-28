import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// What a scanned code turned out to be, so the caller can route it.
enum SmartScanKind { payment, store, product, url, search }

/// The decoded meaning of a scanned/pasted code.
class SmartScanResult {
  final SmartScanKind kind;
  final String raw;
  final String? uid;
  final String? storeId;
  final String? url;
  final Map<String, dynamic>? product;

  const SmartScanResult({
    required this.kind,
    required this.raw,
    this.uid,
    this.storeId,
    this.url,
    this.product,
  });
}

/// WeChat-style smart scan: one scanner understands payment codes, store and
/// product deep links, plain web links, and product barcodes, then tells the
/// caller how to route the result.
class SmartScanService {
  const SmartScanService();

  Future<SmartScanResult> resolve(String raw) async {
    final code = raw.trim();
    if (code.isEmpty) return SmartScanResult(kind: SmartScanKind.search, raw: code);

    final lower = code.toLowerCase();

    // 1) Alfaeq deep links: alfaeq://pay, alfaeq://store, alfaeq://product.
    if (lower.startsWith('alfaeq://')) {
      Uri? uri;
      try {
        uri = Uri.parse(code);
      } catch (_) {}
      if (uri != null) {
        final host = uri.host.toLowerCase();
        final params = uri.queryParameters;
        if (host == 'pay' || lower.startsWith('alfaeq://pay')) {
          final uid = (params['uid'] ?? '').trim();
          if (uid.isNotEmpty) return SmartScanResult(kind: SmartScanKind.payment, raw: code, uid: uid);
        }
        if (host == 'store') {
          final id = _idFrom(params, uri);
          if (id.isNotEmpty) return SmartScanResult(kind: SmartScanKind.store, raw: code, storeId: id);
        }
        if (host == 'product') {
          final id = _idFrom(params, uri);
          final product = await _productByCode(id);
          if (product != null) return SmartScanResult(kind: SmartScanKind.product, raw: code, product: product);
        }
      }
    }

    // 2) Plain web link.
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return SmartScanResult(kind: SmartScanKind.url, raw: code, url: code);
    }

    // 3) Product barcode or product id.
    final product = await _productByCode(code);
    if (product != null) return SmartScanResult(kind: SmartScanKind.product, raw: code, product: product);

    // 4) Fall back to a text search.
    return SmartScanResult(kind: SmartScanKind.search, raw: code);
  }

  /// Reads an id from `?id=` first, then from the first path segment.
  String _idFrom(Map<String, String> params, Uri uri) {
    final fromQuery = (params['id'] ?? '').trim();
    if (fromQuery.isNotEmpty) return fromQuery;
    return uri.pathSegments.isNotEmpty ? uri.pathSegments.first.trim() : '';
  }

  /// Looks a product up by barcode (metadata->>barcode) or by its id.
  Future<Map<String, dynamic>?> _productByCode(String code) async {
    if (code.isEmpty || !SupabaseService.isInitialized) return null;
    final db = SupabaseService.client;
    final safe = code.replaceAll(RegExp(r'[,()%*]'), '').trim();
    if (safe.isEmpty) return null;
    try {
      final byBarcode = await db
          .from('products')
          .select()
          .eq('status', 'active')
          .filter('metadata->>barcode', 'eq', safe)
          .limit(1);
      if (byBarcode.isNotEmpty) return Map<String, dynamic>.from(byBarcode.first);
    } catch (_) {}
    try {
      final row = await db.from('products').select().eq('id', safe).eq('status', 'active').maybeSingle();
      if (row != null) return Map<String, dynamic>.from(row);
    } on PostgrestException {
      // Not found / not a valid id.
    } catch (_) {}
    return null;
  }
}
