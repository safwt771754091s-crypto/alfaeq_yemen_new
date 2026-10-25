import 'supabase_service.dart';

/// Follows (المتابعة): WeChat-style follow graph for stores and users.
class FollowService {
  static final _db = SupabaseService.client;

  /// Returns the new followed state (true = now following).
  Future<bool> toggle({required String targetType, required String targetId}) async {
    final res = await _db.rpc('follow_toggle', params: {
      'p_target_type': targetType,
      'p_target_id': targetId,
    });
    return res == true;
  }

  Future<({int followerCount, bool following})> state({
    required String targetType,
    required String targetId,
  }) async {
    final rows = await _db.rpc('follow_state', params: {
      'p_target_type': targetType,
      'p_target_id': targetId,
    });
    final row = (rows as List).isNotEmpty ? rows.first as Map<String, dynamic> : const {};
    return (
      followerCount: (row['follower_count'] as num?)?.toInt() ?? 0,
      following: row['following'] == true,
    );
  }

  Future<List<Map<String, dynamic>>> myFollows({int limit = 100}) async {
    final rows = await _db.rpc('my_follows', params: {'p_limit': limit});
    return (rows as List).cast<Map<String, dynamic>>();
  }
}
