import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Product/store reviews. Author names are resolved server-side so the users
/// table is never read from the client.
class ReviewService {
  const ReviewService();

  static SupabaseClient get _db => SupabaseService.client;

  String? get currentUserId => _db.auth.currentUser?.id;

  Future<({double average, int count, List<Map<String, dynamic>> items})> productReviews(
    String productId, {
    int limit = 50,
  }) async {
    final data = await _db.rpc('product_reviews', params: {'p_product_id': productId, 'p_limit': limit});
    final map = data is Map ? Map<String, dynamic>.from(data) : const <String, dynamic>{};
    final items = (map['items'] as List?)?.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() ?? const [];
    return (
      average: (map['average'] as num?)?.toDouble() ?? 0,
      count: (map['count'] as num?)?.toInt() ?? 0,
      items: items,
    );
  }

  /// Rating badges for a grid of products: productId -> (average, count).
  Future<Map<String, ({double average, int count})>> summary(List<String> productIds) async {
    if (productIds.isEmpty) return const {};
    final data = await _db.rpc('reviews_summary', params: {'p_product_ids': productIds});
    final rows = data is List ? data.whereType<Map>() : const <Map>[];
    return {
      for (final row in rows)
        (row['product_id'] ?? '').toString(): (
          average: (row['average'] as num?)?.toDouble() ?? 0,
          count: (row['review_count'] as num?)?.toInt() ?? 0,
        ),
    };
  }

  Future<void> submit({
    required String productId,
    required int rating,
    String body = '',
    String? storeId,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('يجب تسجيل الدخول لإضافة تقييم.');
    if (rating < 1 || rating > 5) throw StateError('التقييم يجب أن يكون بين 1 و5 نجوم.');
    try {
      await _db.from('reviews').insert({
        'user_id': uid,
        'product_id': productId,
        'store_id': storeId,
        'rating': rating,
        'body': body.trim(),
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') throw StateError('لقد قيّمت هذا المنتج مسبقاً.');
      rethrow;
    }
  }
}
