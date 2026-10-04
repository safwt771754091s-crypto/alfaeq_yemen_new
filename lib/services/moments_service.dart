import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Data access for the WeChat-style Moments (朋友圈) social feed.
class MomentsService {
  const MomentsService();

  static const bucket = 'moments';

  static SupabaseClient get _db => SupabaseService.client;

  String? get currentUserId => _db.auth.currentUser?.id;

  /// Feed rows are resolved server-side (author name/avatar + liked_by_me) so
  /// the client never has to read the users table directly.
  Future<List<Map<String, dynamic>>> feed({int limit = 40}) async {
    final data = await _db.rpc('moments_feed', params: {'p_limit': limit});
    return _rows(data);
  }

  Future<List<Map<String, dynamic>>> comments(String momentId) async {
    final data = await _db.rpc('moment_comments_list', params: {'p_moment_id': momentId});
    return _rows(data);
  }

  Future<void> publish({
    required String content,
    required List<String> mediaUrls,
    String visibility = 'public',
  }) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('يجب تسجيل الدخول للنشر.');
    await _db.from('moments').insert({
      'author_id': uid,
      'content': content.trim(),
      'media_urls': mediaUrls,
      'visibility': visibility,
    });
  }

  Future<void> setLike(String momentId, bool liked) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('يجب تسجيل الدخول للإعجاب.');
    if (liked) {
      await _db.from('moment_likes').insert({'moment_id': momentId, 'user_id': uid});
    } else {
      await _db.from('moment_likes').delete().eq('moment_id', momentId).eq('user_id', uid);
    }
  }

  Future<void> comment(String momentId, String body) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('يجب تسجيل الدخول للتعليق.');
    final row = await _db
        .from('moment_comments')
        .insert({'moment_id': momentId, 'author_id': uid, 'body': body.trim()})
        .select('id')
        .single();
    final commentId = row['id']?.toString();
    if (commentId != null) {
      // Best-effort: the notification RPC is a no-op for self-comments.
      try {
        await _db.rpc('notify_moment_comment', params: {'p_moment_id': momentId, 'p_comment_id': commentId});
      } catch (_) {}
    }
  }

  Future<void> deleteMoment(String momentId) async {
    await _db.from('moments').delete().eq('id', momentId);
  }

  Future<String> uploadImage(Uint8List bytes, String extension) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('يجب تسجيل الدخول لرفع الصور.');
    final ext = extension.replaceAll('.', '').toLowerCase();
    final safeExt = ext.isEmpty ? 'jpg' : ext;
    final path = '$uid/${DateTime.now().microsecondsSinceEpoch}.$safeExt';
    await _db.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(cacheControl: '31536000', upsert: false),
        );
    return _db.storage.from(bucket).getPublicUrl(path);
  }

  List<Map<String, dynamic>> _rows(Object? data) {
    if (data is List) {
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const [];
  }
}
