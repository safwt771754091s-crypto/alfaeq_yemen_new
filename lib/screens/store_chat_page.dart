import 'package:flutter/material.dart';

import '../services/store_chat_service.dart';
import '../services/supabase_service.dart';

/// WeChat-style "official store account" conversation. The store posts a
/// welcome menu; tapping an option asks the server for an automatic reply with
/// live data (products, the customer's orders, store info).
class StoreChatPage extends StatefulWidget {
  final String threadId;
  final String title;
  const StoreChatPage({super.key, required this.threadId, required this.title});

  @override
  State<StoreChatPage> createState() => _StoreChatPageState();
}

class _StoreChatPageState extends State<StoreChatPage> {
  final _message = TextEditingController();
  bool _sending = false;
  StoreChatStore? _store;
  String? get _uid => SupabaseService.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _markRead();
    _loadStore();
  }

  Future<void> _markRead() async {
    try {
      await SupabaseService.client.rpc('mark_thread_read', params: {'p_thread_id': widget.threadId});
    } catch (_) {/* best-effort */}
  }

  Future<void> _loadStore() async {
    try {
      final info = await const StoreChatService().storeInfo(widget.threadId);
      if (mounted) setState(() => _store = info);
    } catch (_) {/* header falls back to the title */}
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await SupabaseService.client.rpc('send_chat_message', params: {'p_thread_id': widget.threadId, 'p_body': text});
      _message.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إرسال الرسالة: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _menu(String action) async {
    try {
      await const StoreChatService().action(widget.threadId, action);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyStoreChatError(e))));
    }
  }

  Stream<List<Map<String, dynamic>>> _messages() => SupabaseService.client
      .from('chat_messages')
      .stream(primaryKey: ['id'])
      .eq('thread_id', widget.threadId)
      .order('created_at', ascending: true);

  @override
  Widget build(BuildContext context) {
    if (_uid == null) return const Scaffold(body: Center(child: Text('يجب تسجيل الدخول أولاً.')));
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w900)),
          bottom: _store == null || (_store!.phone == null && _store!.address == null)
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(22),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      [_store!.phone, _store!.address].where((v) => v != null && v.isNotEmpty).join(' • '),
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ),
                ),
        ),
        body: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _messages(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) return Center(child: Text('تعذر تحميل الرسائل: ${snapshot.error}'));
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  final messages = snapshot.data ?? const <Map<String, dynamic>>[];
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: messages.length,
                    itemBuilder: (_, i) => _bubble(messages[i]),
                  );
                },
              ),
            ),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _bubble(Map<String, dynamic> row) {
    final mine = row['sender_id']?.toString() == _uid;
    final meta = row['metadata'];
    final kind = meta is Map ? meta['kind']?.toString() : null;
    if (kind == 'store_menu') {
      return _menuBubble(meta as Map, row);
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? Theme.of(context).colorScheme.primaryContainer : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text((row['body'] ?? '').toString()),
      ),
    );
  }

  Widget _menuBubble(Map meta, Map<String, dynamic> row) {
    final options = (meta['options'] is List ? meta['options'] as List : const []);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF07C160)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text((row['body'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            for (final o in options)
              if (o is Map)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF07C160),
                        side: const BorderSide(color: Color(0xFF07C160)),
                        alignment: Alignment.centerRight,
                      ),
                      onPressed: () => _menu((o['action'] ?? '').toString()),
                      icon: const Icon(Icons.chevron_left, size: 18),
                      label: Align(alignment: Alignment.centerRight, child: Text((o['label'] ?? '').toString())),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _composer() => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _message,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'اكتب رسالة للمتجر...',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: _sending ? null : _send, icon: const Icon(Icons.send)),
          ]),
        ),
      );

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }
}
