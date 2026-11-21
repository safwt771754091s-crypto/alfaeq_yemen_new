import 'package:postgrest/postgrest.dart';

import 'supabase_service.dart';
import '../core/query_cache.dart';
import '../core/product_units.dart';

class CatalogDocument {
  final String id;
  final Map<String, dynamic> data;
  const CatalogDocument({required this.id, required this.data});

  factory CatalogDocument.fromSupabase(Map<String, dynamic> row) {
    final copy = Map<String, dynamic>.from(row);
    final id = (copy.remove('id') ?? '').toString();
    return CatalogDocument(id: id, data: copy);
  }

  factory CatalogDocument.fromLegacyMap(Map<String, dynamic> data, {String? id}) {
    return CatalogDocument(id: id ?? (data['id'] ?? data['productId'] ?? '').toString(), data: Map<String, dynamic>.from(data));
  }

}

class CatalogPage {
  final List<CatalogDocument> items;
  final int total;
  const CatalogPage({required this.items, required this.total});
}

class CatalogService {
  final bool useSupabase;

  const CatalogService({this.useSupabase = true});

  /// PostgREST (Supabase) caps every response at 1000 rows regardless of the
  /// requested `limit`, so a single `.limit(5000)` silently truncates the
  /// catalog. Callers that need the whole list must page through it.
  static const int maxRowsPerRequest = 1000;

  /// Resolves a scanned or typed barcode to the products that carry it.
  ///
  /// `metadata` is too large to ship with every catalog row (about 700 bytes
  /// each), so the lookup runs server-side and only matches come back.
  Future<List<CatalogDocument>> searchBarcode(String barcode) {
    final code = barcode.trim();
    if (code.isEmpty) return Future.value(const []);
    return QueryCache.instance.remember(
      'catalog.barcode.$code',
      () async {
        final rows = await SupabaseService.client
            .from('products')
            .select(_productColumns)
            .eq('status', 'active')
            .filter('metadata->>barcode', 'eq', code)
            .limit(50);
        return rows
            .map((row) => CatalogDocument.fromSupabase(Map<String, dynamic>.from(row)))
            .toList();
      },
      ttl: QueryCache.contentTtl,
    );
  }

  Future<List<CatalogDocument>> activeProducts({String? storeId, String? sectionId, int limit = 100}) async {
    if (!useSupabase || !SupabaseService.isInitialized) {
      throw StateError('خدمة الكتالوج الجديدة غير مفعلة.');
    }
    final key = 'catalog.products.$storeId.$sectionId.$limit';
    return QueryCache.instance.remember(
      key,
      () async {
        var query = SupabaseService.client
            .from('products')
            .select(_productColumns)
            .eq('status', 'active');
        if (storeId != null && storeId.isNotEmpty) query = query.eq('store_id', storeId);
        if (sectionId != null && sectionId.isNotEmpty) query = query.eq('section_id', sectionId);
        final rows = await query.order('name').limit(limit);
        return rows.map((row) => CatalogDocument.fromSupabase(Map<String, dynamic>.from(row))).toList();
      },
      ttl: QueryCache.contentTtl,
    );
  }

  /// The columns the storefront actually renders. Selecting `*` sent 265 KB for
  /// 200 products; this projection sends 103 KB for the same rows.
  ///
  /// Verified against the live schema: `category`, `unit`, and `original_price`
  /// do not exist on `products`, and selecting them fails the whole request.
  ///
  /// `metadata` is deliberately excluded. It carries the import audit trail
  /// (about 700 bytes per row) and the only field the UI reads from it is
  /// `barcode`, which [searchBarcode] resolves server-side.
  static const String _productColumns =
      'id,name,price,currency,stock,image_url,description,section_id,'
      'store_id,owner_id,status,sale_unit,stock_base,min_order_base,step_base';

  /// Exposed so a test can assert the projection stays in sync with the UI.
  static List<String> get productColumnsForTest => _productColumns.split(',');

  /// Fetches every matching active product by walking 1000-row pages, and
  /// reports the true server-side total so the UI can show progress.
  /// [onProgress] receives (loaded, total) after each page.
  Future<CatalogPage> activeProductsPaged({
    String? storeId,
    String? sectionId,
    void Function(int loaded, int total)? onProgress,
    int pageSize = maxRowsPerRequest,
  }) async {
    if (!useSupabase || !SupabaseService.isInitialized) {
      throw StateError('خدمة الكتالوج الجديدة غير مفعلة.');
    }
    final client = SupabaseService.client;
    final size = pageSize.clamp(1, maxRowsPerRequest);

    PostgrestFilterBuilder<List<Map<String, dynamic>>> build() {
      var query = client.from('products').select(_productColumns).eq('status', 'active');
      if (storeId != null && storeId.isNotEmpty) query = query.eq('store_id', storeId);
      if (sectionId != null && sectionId.isNotEmpty) query = query.eq('section_id', sectionId);
      return query;
    }

    final first = await build().order('name').range(0, size - 1).count(CountOption.exact);
    final items = first.data
        .map((row) => CatalogDocument.fromSupabase(Map<String, dynamic>.from(row)))
        .toList();
    final total = first.count;
    onProgress?.call(items.length, total);

    // The exact count is known after the first page, so every remaining offset
    // is known too. Requesting them concurrently keeps a large section to one
    // round trip instead of one per page.
    final offsets = <int>[
      for (var offset = size; offset < total; offset += size) offset,
    ];
    if (offsets.isEmpty) return CatalogPage(items: items, total: total);

    final pages = await Future.wait(
      offsets.map((offset) => build().order('name').range(offset, offset + size - 1)),
    );
    for (final page in pages) {
      if (page.isEmpty) continue;
      items.addAll(page.map((row) => CatalogDocument.fromSupabase(Map<String, dynamic>.from(row))));
      onProgress?.call(items.length, total);
    }

    return CatalogPage(items: items, total: total);
  }

  Future<List<CatalogDocument>> approvedStores(String sectionId, {int limit = 30}) async {
    if (!useSupabase || !SupabaseService.isInitialized) {
      throw StateError('خدمة الكتالوج الجديدة غير مفعلة.');
    }
    return QueryCache.instance.remember(
      'catalog.stores.section.$sectionId.$limit',
      () async {
        final rows = await SupabaseService.client
            .from('stores')
            .select(_storeColumns)
            .eq('section_id', sectionId)
            .eq('status', 'approved')
            .order('name')
            .limit(limit);
        return rows.map((row) => CatalogDocument.fromSupabase(Map<String, dynamic>.from(row))).toList();
      },
      ttl: QueryCache.contentTtl,
    );
  }

  /// Columns rendered by the store list and store card, verified against the
  /// live schema (`image_url`, `description`, and `rating` do not exist here).
  static List<String> get storeColumnsForTest => _storeColumns.split(',');

  static const String _storeColumns =
      'id,name,address,phone,section_id,owner_id,status,created_at';

  /// Every approved/active store regardless of section — powers the flat
  /// "all stores" list so merchants are discoverable without knowing a section.
  Future<List<CatalogDocument>> allApprovedStores({int limit = 200}) async {
    if (!useSupabase || !SupabaseService.isInitialized) {
      throw StateError('خدمة الكتالوج الجديدة غير مفعلة.');
    }
    return QueryCache.instance.remember(
      'catalog.stores.all.$limit',
      () async {
        final rows = await SupabaseService.client
            .from('stores')
            .select(_storeColumns)
            .inFilter('status', ['approved', 'active'])
            .order('name')
            .limit(limit);
        return rows.map((row) => CatalogDocument.fromSupabase(Map<String, dynamic>.from(row))).toList();
      },
      ttl: QueryCache.contentTtl,
    );
  }

  /// A single store by id, for deep links (e.g. opening a followed store).
  Future<CatalogDocument> storeById(String id) async {
    if (!useSupabase || !SupabaseService.isInitialized) {
      throw StateError('خدمة الكتالوج الجديدة غير مفعلة.');
    }
    final row = await SupabaseService.client.from('stores').select().eq('id', id).maybeSingle();
    if (row == null) throw StateError('المتجر غير موجود');
    return CatalogDocument.fromSupabase(Map<String, dynamic>.from(row));
  }

  Future<void> addToCart(String uid, CatalogDocument product, {num? saleQuantity}) async {
    if (!useSupabase || !SupabaseService.isInitialized) {
      throw StateError('خدمة السلة الجديدة غير مفعلة.');
    }

    final p = product.data;
    final price = p['price'];
    if (price is! num || price < 0) throw StateError('سعر الصنف غير صالح.');
    final unit = ProductUnit.fromProduct(p);
    final stockBase = ProductUnit.stockBase(p);
    final stepBase = unit.stepFor(p);
    final stock = p['stock_base'] ?? p['stock'];
    if (stock is num && stock <= 0) throw StateError('هذا الصنف غير متوفر حالياً.');

    final client = SupabaseService.client;
    final existing = await client.from('carts').select('items').eq('uid', uid).maybeSingle();
    final raw = existing?['items'];
    final items = raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];

    // A single cart has one currency; the server rejects mixed-currency orders,
    // so block it here with a clear message instead of failing at checkout.
    final productCurrency = (p['currency'] ?? 'YER').toString().toUpperCase();
    final cartCurrency = items.isEmpty
        ? productCurrency
        : (items.first['currency'] ?? productCurrency).toString().toUpperCase();
    if (items.isNotEmpty && cartCurrency != productCurrency) {
      throw StateError('لا يمكن خلط أصناف بعملات مختلفة في سلة واحدة. أفرغ السلة أو أضف أصنافًا بعملة $cartCurrency.');
    }

    final index = items.indexWhere(
      (item) => item['productId'] == product.id || item['product_id'] == product.id,
    );

    // Quantity requested from a product page, in sale units (e.g. 2 كجم).
    final requestedBase = saleQuantity == null ? null : unit.toBase(saleQuantity).round();

    if (index >= 0) {
      final rawBase = items[index]['quantityBase'] ?? items[index]['quantity_base'];
      final currentBase = rawBase is num
          ? rawBase.round()
          : (((items[index]['quantity'] as num?) ?? 1) * unit.scale).round();
      final nextBase = requestedBase ?? (currentBase + stepBase);
      if (stockBase > 0 && nextBase > stockBase) throw StateError('لا يمكن تجاوز الكمية المتوفرة.');
      if (nextBase > unit.scale * 100) throw StateError('الحد الأقصى للكمية المطلوبة هو 100 وحدة بيع.');
      items[index]['quantityBase'] = nextBase;
      items[index]['quantity'] = unit.fromBase(nextBase);
    } else {
      final base = requestedBase ?? unit.scale;
      if (stockBase > 0 && base > stockBase) throw StateError('لا يمكن تجاوز الكمية المتوفرة.');
      if (base > unit.scale * 100) throw StateError('الحد الأقصى للكمية المطلوبة هو 100 وحدة بيع.');
      items.add({
        'productId': product.id,
        'name': (p['name'] ?? p['title'] ?? 'صنف').toString(),
        'price': price,
        'currency': p['currency'] ?? 'YER',
        'quantity': unit.fromBase(base),
        'quantityBase': base,
        'unitScale': unit.scale,
        'saleUnit': unit.id,
        'unitLabel': unit.label,
        'baseUnit': unit.baseUnit,
        'stepBase': stepBase,
        'minOrderBase': unit.minFor(p),
        'storeId': p['store_id'] ?? p['storeId'] ?? '',
        'merchantId': p['owner_id'] ?? p['ownerId'] ?? '',
        'ownerId': p['owner_id'] ?? p['ownerId'] ?? '',
        'imageUrl': p['image_url'] ?? p['imageUrl'] ?? p['image'] ?? '',
      });
    }

    await client.from('carts').upsert({
      'uid': uid,
      'owner_id': uid,
      'items': items,
      'metadata': <String, dynamic>{},
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'uid');
  }
}
