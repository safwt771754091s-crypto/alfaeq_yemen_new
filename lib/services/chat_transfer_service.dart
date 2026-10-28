import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// WeChat Pay-style peer-to-peer transfer inside a 1:1 chat. All money movement
/// stays inside SECURITY DEFINER RPCs; the client only passes intent.
class ChatTransferService {
  const ChatTransferService();

  SupabaseClient get _c => SupabaseService.client;

  /// The other participant of a direct thread, or null for a group thread /
  /// when the caller is not a member.
  Future<ChatPeer?> peer(String threadId) async {
    final res = await _c.rpc('direct_thread_peer', params: {'p_thread_id': threadId});
    final row = (res is List ? (res.isEmpty ? null : res.first) : res);
    if (row is! Map) return null;
    final uid = (row['peer_uid'] ?? '').toString();
    if (uid.isEmpty) return null;
    return ChatPeer(uid: uid, name: (row['peer_name'] ?? 'مستخدم الفائق').toString());
  }

  /// Moves [amount] from the caller to [toUid] and posts a chat bubble.
  /// Returns the sender's new balance in [ChatTransferResult.balance].
  Future<ChatTransferResult> send({
    required String threadId,
    required String toUid,
    required num amount,
    String? note,
    String? idempotencyKey,
  }) async {
    final idem = idempotencyKey ?? 'chatxfer-${DateTime.now().microsecondsSinceEpoch}';
    final res = await _c.rpc('chat_transfer_send', params: {
      'p_thread_id': threadId,
      'p_to_uid': toUid,
      'p_amount': amount,
      'p_idempotency_key': idem,
      'p_note': note,
    });
    final row = (res is List ? (res.isEmpty ? null : res.first) : res);
    if (row is! Map) throw const PostgrestException(message: 'تعذر تنفيذ التحويل.');
    return ChatTransferResult.fromMap(Map<String, dynamic>.from(row));
  }
}

class ChatPeer {
  final String uid;
  final String name;
  const ChatPeer({required this.uid, required this.name});
}

class ChatTransferResult {
  final String? messageId;
  final num balance;
  final String currency;
  final num amount;
  final String toUid;
  const ChatTransferResult({
    required this.messageId,
    required this.balance,
    required this.currency,
    required this.amount,
    required this.toUid,
  });

  factory ChatTransferResult.fromMap(Map<String, dynamic> m) => ChatTransferResult(
        messageId: m['message_id']?.toString(),
        balance: (m['balance'] as num?) ?? 0,
        currency: (m['currency'] ?? 'YER').toString(),
        amount: (m['amount'] as num?) ?? 0,
        toUid: (m['to_uid'] ?? '').toString(),
      );
}

/// Turns the gateway's error codes into a short Arabic message.
String friendlyChatTransferError(Object e) {
  final t = e.toString();
  if (t.contains('insufficient_wallet_balance')) return 'رصيد المحفظة غير كافٍ.';
  if (t.contains('cannot_pay_self')) return 'لا يمكنك التحويل لنفسك.';
  if (t.contains('recipient_not_found')) return 'المستلم غير موجود.';
  if (t.contains('recipient_currency_mismatch')) return 'عملة المستلم غير متوافقة.';
  if (t.contains('transfer_requires_direct_thread')) return 'التحويل متاح في المحادثات الفردية فقط.';
  if (t.contains('recipient_not_in_thread')) return 'المستلم ليس طرفاً في هذه المحادثة.';
  if (t.contains('not_a_member')) return 'أنت لست عضواً في هذه المحادثة.';
  if (t.contains('wallet_missing')) return 'لا توجد محفظة نشطة. فعّل محفظتك أولاً.';
  if (t.contains('invalid_amount')) return 'أدخل مبلغاً صالحاً.';
  if (t.contains('idempotency_required')) return 'تعذر تأمين العملية، حاول مرة أخرى.';
  return 'تعذر إتمام التحويل. حاول مرة أخرى.';
}
