import 'supabase_service.dart';
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

class CatalogService {
  final bool useSupabase;

  const CatalogService({this.useSupabase = true});

  Future<List<CatalogDocument>> activeProducts({String? storeId, String? sectionId, int limit = 100}) async {
    if (!useSupabase || !SupabaseService.isInitialized) {
      throw StateError('خدمة الكتالوج الجديدة غير مفعلة.');
    }
    var query = SupabaseService.client.from('products').select().eq('status', 'active');
    if (storeId != null && storeId.isNotEmpty) query = query.eq('store_id', storeId);
    if (sectionId != null && sectionId.isNotEmpty) query = query.eq('section_id', sectionId);
    final rows = await query.order('name').limit(limit);
    return rows.map((row) => CatalogDocument.fromSupabase(Map<String, dynamic>.from(row))).toList();
  }

  Future<List<CatalogDocument>> approvedStores(String sectionId, {int limit = 30}) async {
    if (!useSupabase || !SupabaseService.isInitialized) {
      throw StateError('خدمة الكتالوج الجديدة غير مفعلة.');
    }
    final rows = await SupabaseService.client
        .from('stores')
        .select()
        .eq('section_id', sectionId)
        .eq('status', 'approved')
        .order('name')
        .limit(limit);
    return rows.map((row) => CatalogDocument.fromSupabase(Map<String, dynamic>.from(row))).toList();
  }

  /// Every approved/active store regardless of section — powers the flat
  /// "all stores" list so merchants are discoverable without knowing a section.
  Future<List<CatalogDocument>> allApprovedStores({int limit = 200}) async {
    if (!useSupabase || !SupabaseService.isInitialized) {
      throw StateError('خدمة الكتالوج الجديدة غير مفعلة.');
    }
    final rows = await SupabaseService.client
        .from('stores')
        .select()
        .inFilter('status', ['approved', 'active'])
        .order('name')
        .limit(limit);
    return rows.map((row) => CatalogDocument.fromSupabase(Map<String, dynamic>.from(row))).toList();
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
