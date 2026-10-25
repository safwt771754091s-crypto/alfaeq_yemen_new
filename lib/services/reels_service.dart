import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Data access for the WeChat-Channels style short-video feed (فيديو الفائق).
class ReelsService {
  const ReelsService();

  static const bucket = 'reels';

  static SupabaseClient get _db => SupabaseService.client;

  String? get currentUserId => _db.auth.currentUser?.id;

  /// Feed rows are resolved server-side (author name/avatar + liked_by_me) so
  /// the client never has to read the users table directly.
  Future<List<Map<String, dynamic>>> feed({int limit = 30, int offset = 0}) async {
    final data = await _db.rpc('reels_feed', params: {'p_limit': limit, 'p_offset': offset});
    return _rows(data);
  }

  Future<List<Map<String, dynamic>>> comments(String reelId) async {
    final data = await _db.rpc('reel_comments_list', params: {'p_reel_id': reelId});
    return _rows(data);
  }

  Future<void> publish({
    required String caption,
    required String videoUrl,
    String? thumbnailUrl,
    int durationSeconds = 0,
    String kind = 'video',
    String visibility = 'public',
  }) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('يجب تسجيل الدخول للنشر.');
    await _db.from('reels').insert({
      'author_id': uid,
      'caption': caption.trim(),
      'video_url': videoUrl,
      'thumbnail_url': thumbnailUrl,
      'duration_seconds': durationSeconds,
      'kind': kind,
      'visibility': visibility,
    });
  }

  Future<void> setLike(String reelId, bool liked) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('يجب تسجيل الدخول للإعجاب.');
    if (liked) {
      await _db.from('reel_likes').insert({'reel_id': reelId, 'user_id': uid});
    } else {
      await _db.from('reel_likes').delete().eq('reel_id', reelId).eq('user_id', uid);
    }
  }

  Future<void> comment(String reelId, String body) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('يجب تسجيل الدخول للتعليق.');
    final row = await _db
        .from('reel_comments')
        .insert({'reel_id': reelId, 'author_id': uid, 'body': body.trim()})
        .select('id')
        .single();
    final commentId = row['id']?.toString();
    if (commentId != null) {
      // Best-effort: the notification RPC is a no-op for self-comments.
      try {
        await _db.rpc('notify_reel_comment', params: {'p_reel_id': reelId, 'p_comment_id': commentId});
      } catch (_) {}
    }
  }

  Future<void> registerView(String reelId) async {
    try {
      await _db.rpc('reel_register_view', params: {'p_reel_id': reelId});
    } catch (_) {
      // Views are best-effort telemetry; never block playback on them.
    }
  }

  Future<void> deleteReel(String reelId) async {
    await _db.from('reels').delete().eq('id', reelId);
  }

  /// Uploads a video (or its poster image) and returns the public URL.
  Future<String> uploadMedia(Uint8List bytes, String extension, {String folder = 'videos'}) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('يجب تسجيل الدخول للرفع.');
    final ext = extension.replaceAll('.', '').toLowerCase();
    final safeExt = ext.isEmpty ? 'mp4' : ext;
    final path = '$uid/$folder/${DateTime.now().microsecondsSinceEpoch}.$safeExt';
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
