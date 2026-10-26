import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// WeChat-style red packets (حزمة حمراء). All money movement happens inside
/// SECURITY DEFINER RPCs; the client only passes intent.
class RedPacketService {
  const RedPacketService();

  SupabaseClient get _c => SupabaseService.client;

  /// Locks [total] from the caller's wallet and shares the packet into a chat.
  Future<String> create({
    required String threadId,
    required num total,
    int count = 1,
    String? wish,
    String type = 'random',
    String? message,
  }) async {
    final res = await _c.rpc('red_packet_create', params: {
      'p_thread_id': threadId,
      'p_total': total,
      'p_count': count,
      'p_wish': wish,
      'p_packet_type': type,
      'p_message': message,
    });
    return res.toString();
  }

  /// Opens a packet for the current user. Returns the claim result.
  Future<RedPacketOpenResult> open(String packetId) async {
    final res = await _c.rpc('red_packet_open', params: {'p_packet_id': packetId});
    final row = (res is List ? (res.isEmpty ? null : res.first) : res);
    if (row is! Map) throw const PostgrestException(message: 'تعذر فتح الحزمة.');
    return RedPacketOpenResult.fromMap(Map<String, dynamic>.from(row));
  }

  Future<Map<String, dynamic>?> details(String packetId) async {
    final res = await _c.rpc('red_packet_details', params: {'p_packet_id': packetId});
    final row = (res is List ? (res.isEmpty ? null : res.first) : res);
    return row is Map ? Map<String, dynamic>.from(row) : null;
  }

  Future<List<Map<String, dynamic>>> claims(String packetId) async {
    final res = await _c.rpc('red_packet_claims_list', params: {'p_packet_id': packetId});
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Sender refunds the unopened balance of an expired packet.
  Future<num> reclaim(String packetId) async {
    final res = await _c.rpc('red_packet_reclaim', params: {'p_packet_id': packetId});
    return num.tryParse('$res') ?? 0;
  }
}

class RedPacketOpenResult {
  final String packetId;
  final num amount;
  final bool alreadyOpened;
  final bool finished;
  final String senderUid;
  final num remainingAmount;
  final int openedCount;
  final int shareCount;
  final String currency;
  final String? wish;

  const RedPacketOpenResult({
    required this.packetId,
    required this.amount,
    required this.alreadyOpened,
    required this.finished,
    required this.senderUid,
    required this.remainingAmount,
    required this.openedCount,
    required this.shareCount,
    required this.currency,
    this.wish,
  });

  factory RedPacketOpenResult.fromMap(Map<String, dynamic> m) => RedPacketOpenResult(
        packetId: m['packet_id'].toString(),
        amount: (m['amount'] as num?) ?? 0,
        alreadyOpened: m['already_opened'] == true,
        finished: m['finished'] == true,
        senderUid: (m['sender_uid'] ?? '').toString(),
        remainingAmount: (m['remaining_amount'] as num?) ?? 0,
        openedCount: (m['opened_count'] as num?)?.toInt() ?? 0,
        shareCount: (m['share_count'] as num?)?.toInt() ?? 0,
        currency: (m['currency'] ?? 'YER').toString(),
        wish: m['wish']?.toString(),
      );
}
