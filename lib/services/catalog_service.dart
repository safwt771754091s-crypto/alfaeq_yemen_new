import 'package:cloud_firestore/cloud_firestore.dart';
import 'supabase_service.dart';

class CatalogDocument {
  final String id;
  final Map<String, dynamic> data;
  const CatalogDocument({required this.id, required this.data});

  factory CatalogDocument.fromSupabase(Map<String, dynamic> row) {
    final copy = Map<String, dynamic>.from(row);
    final id = (copy.remove('id') ?? '').toString();
    return CatalogDocument(id: id, data: copy);
  }

  factory CatalogDocument.fromFirestore(QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
      CatalogDocument(id: doc.id, data: doc.data());
}

class CatalogService {
  final bool useSupabase;

  const CatalogService({this.useSupabase = true});

  Future<List<CatalogDocument>> activeProducts({String? storeId, int limit = 100}) async {
    if (useSupabase && SupabaseService.isInitialized) {
      try {
        var query = SupabaseService.client.from('products').select().eq('status', 'active');
        if (storeId != null && storeId.isNotEmpty) query = query.eq('store_id', storeId);
        final rows = await query.order('name').limit(limit);
        return rows.map((row) => CatalogDocument.fromSupabase(Map<String, dynamic>.from(row))).toList();
      } catch (_) {
        // Migration fallback: keep the legacy catalog readable if Supabase is unavailable.
      }
    }

    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection('products').where('status', isEqualTo: 'active').limit(limit);
    if (storeId != null && storeId.isNotEmpty) query = query.where('storeId', isEqualTo: storeId);
    final snap = await query.get();
    return snap.docs.map((doc) => CatalogDocument(id: doc.id, data: doc.data())).toList();
  }

  Future<List<CatalogDocument>> approvedStores(String sectionId, {int limit = 30}) async {
    if (useSupabase && SupabaseService.isInitialized) {
      try {
        final rows = await SupabaseService.client
            .from('stores')
            .select()
            .eq('section_id', sectionId)
            .eq('status', 'approved')
            .order('name')
            .limit(limit);
        return rows.map((row) => CatalogDocument.fromSupabase(Map<String, dynamic>.from(row))).toList();
      } catch (_) {}
    }

    final snap = await FirebaseFirestore.instance.collection('stores').where('sectionId', isEqualTo: sectionId).where('status', isEqualTo: 'approved').limit(limit).get();
    return snap.docs.map((doc) => CatalogDocument.fromFirestore(doc)).toList();
  }

  Future<void> addToCart(String uid, CatalogDocument product) async {
    final p = product.data;
    final price = p['price'];
    if (price is! num || price < 0) throw StateError('سعر الصنف غير صالح.');

    final stock = p['stock_base'] ?? p['stock'];
    if (stock is num && stock <= 0) throw StateError('هذا الصنف غير متوفر حالياً.');

    if (useSupabase && SupabaseService.isInitialized) {
      final client = SupabaseService.client;
      final existing = await client.from('carts').select('items').eq('uid', uid).maybeSingle();
      final raw = existing?['items'];
      final items = raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
      final index = items.indexWhere((item) => item['productId'] == product.id || item['product_id'] == product.id);
      if (index >= 0) {
        final current = (items[index]['quantity'] as num?)?.toInt() ?? 1;
        final next = current + 1;
        if (stock is num && next > stock.toInt()) throw StateError('لا يمكن تجاوز الكمية المتوفرة.');
        if (next > 100) throw StateError('الحد الأقصى 100 قطعة للصنف.');
        items[index]['quantity'] = next;
      } else {
        items.add({
          'productId': product.id,
          'name': (p['name'] ?? p['title'] ?? 'صنف').toString(),
          'price': price,
          'currency': p['currency'] ?? 'YER',
          'quantity': 1,
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
      return;
    }

    final cartRef = FirebaseFirestore.instance.collection('carts').doc(uid);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(cartRef);
      final cart = snap.data() ?? <String, dynamic>{};
      final rawItems = cart['items'];
      final items = rawItems is List ? rawItems.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
      final index = items.indexWhere((item) => item['productId'] == product.id);
      if (index >= 0) {
        final current = (items[index]['quantity'] as num?)?.toInt() ?? 1;
        final next = current + 1;
        if (stock is num && next > stock.toInt()) throw StateError('لا يمكن تجاوز الكمية المتوفرة.');
        if (next > 100) throw StateError('الحد الأقصى 100 قطعة للصنف.');
        items[index]['quantity'] = next;
      } else {
        items.add({
          'productId': product.id,
          'name': (p['name'] ?? p['title'] ?? 'صنف').toString(),
          'price': price,
          'currency': p['currency'] ?? 'YER',
          'quantity': 1,
          'storeId': p['storeId'] ?? '',
          'merchantId': p['merchantId'] ?? p['ownerId'] ?? '',
          'ownerId': p['ownerId'] ?? '',
          'imageUrl': p['imageUrl'] ?? p['image'] ?? '',
          'addedAt': Timestamp.now(),
        });
      }
      tx.set(cartRef, {'ownerId': uid, 'customerId': uid, 'items': items, 'currency': p['currency'] ?? cart['currency'] ?? 'YER', 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    });
  }
}
