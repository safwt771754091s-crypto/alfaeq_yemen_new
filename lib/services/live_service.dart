import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Data access for WeChat-style live rooms (غرف البث).
///
/// The video transport itself is delegated to the host's streaming tool: this
/// service owns the platform layer (lobby, chat, gifts, viewer counts).
class LiveService {
  const LiveService();

  static SupabaseClient get _db => SupabaseService.client;

  String? get currentUserId => _db.auth.currentUser?.id;

  Future<List<Map<String, dynamic>>> rooms({String status = 'live', int limit = 30}) async {
    final data = await _db.rpc('live_rooms_feed', params: {'p_status': status, 'p_limit': limit});
    return _rows(data);
  }

  Future<List<Map<String, dynamic>>> messages(String roomId, {int limit = 100}) async {
    final data = await _db.rpc('live_messages_list', params: {'p_room_id': roomId, 'p_limit': limit});
    return _rows(data);
  }

  /// Starts a room for the current user and returns its id.
  Future<String> startRoom({required String title, String? playbackUrl}) async {
    final data = await _db.rpc('live_start_room', params: {
      'p_title': title.trim(),
      'p_playback_url': playbackUrl?.trim(),
    });
    return data.toString();
  }

  Future<void> endRoom(String roomId) async {
    await _db.rpc('live_end_room', params: {'p_room_id': roomId});
  }

  Future<void> sendMessage(String roomId, String body, {String kind = 'chat'}) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('يجب تسجيل الدخول.');
    await _db.from('live_messages').insert({
      'room_id': roomId,
      'author_id': uid,
      'body': body.trim(),
      'kind': kind,
    });
  }

  Future<void> sendGift(String roomId, String gift) async {
    await sendMessage(roomId, gift, kind: 'gift');
  }

  /// The room's product shelf (الشراء أثناء البث), as the viewer sees it.
  Future<List<Map<String, dynamic>>> shelf(String roomId) async {
    final data = await _db.rpc('live_room_products_list', params: {'p_room_id': roomId});
    return _rows(data);
  }

  Future<void> addToShelf(String roomId, String productId) async {
    await _db.rpc('live_room_products_add', params: {'p_room_id': roomId, 'p_product_id': productId});
  }

  Future<void> removeFromShelf(String roomId, String productId) async {
    await _db.rpc('live_room_products_remove', params: {'p_room_id': roomId, 'p_product_id': productId});
  }

  /// Shelf stream so a product added mid-stream appears without a refresh.
  Stream<List<Map<String, dynamic>>> shelfStream(String roomId) => _db
      .from('live_room_products')
      .stream(primaryKey: ['room_id', 'product_id'])
      .eq('room_id', roomId)
      .map((rows) => rows.map((e) => Map<String, dynamic>.from(e)).toList());

  Future<void> setLike(String roomId, bool liked) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('يجب تسجيل الدخول.');
    if (liked) {
      await _db.from('live_likes').insert({'room_id': roomId, 'user_id': uid});
    } else {
      await _db.from('live_likes').delete().eq('room_id', roomId).eq('user_id', uid);
    }
  }

  /// Best-effort viewer presence ping (+1 on join, -1 on leave).
  Future<void> registerView(String roomId, int delta) async {
    try {
      await _db.rpc('live_register_view', params: {'p_room_id': roomId, 'p_delta': delta});
    } catch (_) {
      // Presence is telemetry; never block the room on it.
    }
  }

  /// Live chat stream for a room. Falls back to polling when realtime is off.
  Stream<List<Map<String, dynamic>>> messagesStream(String roomId) => _db
      .from('live_messages')
      .stream(primaryKey: ['id'])
      .eq('room_id', roomId)
      .order('created_at')
      .map((rows) => rows.map((e) => Map<String, dynamic>.from(e)).toList());

  /// Lobby stream so newly started rooms appear without a manual refresh.
  Stream<List<Map<String, dynamic>>> roomsStream() => _db
      .from('live_rooms')
      .stream(primaryKey: ['id'])
      .order('created_at')
      .map((rows) => rows.map((e) => Map<String, dynamic>.from(e)).toList());

  List<Map<String, dynamic>> _rows(Object? data) {
    if (data is List) {
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const [];
  }
}
