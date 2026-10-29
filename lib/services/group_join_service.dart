import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// WeChat-style group QR: a group can be shared as a code that others scan to
/// join. All membership changes happen server-side in the `join_group_by_code`
/// RPC; the client never inserts into `chat_members` directly.
class GroupJoinService {
  const GroupJoinService();

  static SupabaseClient get _db => SupabaseService.client;

  /// Reads the group's shareable code, creating it on first use. Pass
  /// [rotate] to invalidate the previous code (e.g. after a leak).
  Future<String> joinCode(String threadId, {bool rotate = false}) async {
    final res = await _db.rpc('group_join_code', params: {'p_thread_id': threadId, 'p_rotate': rotate});
    final code = res?.toString().trim() ?? '';
    if (code.isEmpty) throw StateError('تعذر إنشاء رمز المجموعة.');
    return code;
  }

  /// Joins the group encoded by [code] and returns its thread id. Throws a
  /// friendly error when the code is wrong or revoked.
  Future<String> joinByCode(String code) async {
    try {
      final res = await _db.rpc('join_group_by_code', params: {'p_code': code});
      final id = res?.toString().trim() ?? '';
      if (id.isEmpty) throw StateError('رمز المجموعة غير صالح.');
      return id;
    } on PostgrestException catch (e) {
      if (e.message.contains('invalid_code')) throw StateError('رمز المجموعة غير صالح أو منتهٍ.');
      if (e.message.contains('not_authenticated')) throw StateError('يجب تسجيل الدخول أولاً.');
      rethrow;
    }
  }

  /// The QR / deep-link payload for a group code.
  static String payload(String code) => 'alfaeq://group?code=$code';

  /// Accepts a full `alfaeq://group?code=...` link, a bare code, or text that
  /// contains the link, and returns just the code (or null if none is found).
  static String? extractCode(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    if (value.toLowerCase().startsWith('alfaeq://')) {
      try {
        final uri = Uri.parse(value);
        if (uri.host.toLowerCase() == 'group') {
          final fromQuery = (uri.queryParameters['code'] ?? '').trim();
          if (fromQuery.isNotEmpty) return fromQuery;
          if (uri.pathSegments.isNotEmpty) {
            final fromPath = uri.pathSegments.first.trim();
            if (fromPath.isNotEmpty) return fromPath;
          }
        }
      } catch (_) {}
      return null;
    }
    // A bare code: letters/digits only, no spaces.
    if (RegExp(r'^[A-Za-z0-9]{4,64}$').hasMatch(value)) return value;
    return null;
  }
}
