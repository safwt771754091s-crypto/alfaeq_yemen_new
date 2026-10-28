import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// WeChat-style "official store account" chat. All store replies are produced
/// server-side (SECURITY DEFINER RPCs); the client only sends intent.
class StoreChatService {
  const StoreChatService();

  SupabaseClient get _c => SupabaseService.client;

  /// Opens (or reuses) the caller's conversation with a store. The first open
  /// posts the store's welcome menu. Returns the thread id.
  Future<String> start(String storeId) async {
    final res = await _c.rpc('start_store_thread', params: {'p_store_id': storeId});
    return res.toString();
  }

  /// Store contact card for a store thread (name / phone / address).
  Future<StoreChatStore?> storeInfo(String threadId) async {
    final res = await _c.rpc('store_chat_store', params: {'p_thread_id': threadId});
    final row = (res is List ? (res.isEmpty ? null : res.first) : res);
    if (row is! Map) return null;
    return StoreChatStore.fromMap(Map<String, dynamic>.from(row));
  }

  /// Triggers an automatic store reply for a tapped menu item
  /// (`products` | `orders` | `info`).
  Future<void> action(String threadId, String action) async {
    await _c.rpc('store_chat_action', params: {'p_thread_id': threadId, 'p_action': action});
  }
}

class StoreChatStore {
  final String storeId;
  final String name;
  final String? phone;
  final String? address;
  const StoreChatStore({required this.storeId, required this.name, this.phone, this.address});

  factory StoreChatStore.fromMap(Map<String, dynamic> m) => StoreChatStore(
        storeId: (m['store_id'] ?? '').toString(),
        name: (m['store_name'] ?? 'متجر').toString(),
        phone: (m['phone'] ?? '').toString().isEmpty ? null : m['phone'].toString(),
        address: (m['address'] ?? '').toString().isEmpty ? null : m['address'].toString(),
      );
}

/// Turns the gateway's error codes into a short Arabic message.
String friendlyStoreChatError(Object e) {
  final t = e.toString();
  if (t.contains('store_not_found')) return 'المتجر غير متاح حالياً.';
  if (t.contains('store_required')) return 'لم يتم تحديد المتجر.';
  if (t.contains('not_a_store_thread')) return 'هذه المحادثة ليست محادثة متجر.';
  if (t.contains('not_a_member')) return 'أنت لست عضواً في هذه المحادثة.';
  if (t.contains('unknown_action')) return 'خيار غير معروف.';
  return 'تعذر إتمام العملية. حاول مرة أخرى.';
}
