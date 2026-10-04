import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

class SupportChatPage extends StatefulWidget {
  final String? initialThreadId;
  const SupportChatPage({super.key, this.initialThreadId});
  @override State<SupportChatPage> createState() => _SupportChatPageState();
}

class _SupportChatPageState extends State<SupportChatPage> {
  final _message = TextEditingController();
  String? _threadId;
  bool _creating = false, _sending = false;
  String? get _uid => SupabaseService.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _threadId = widget.initialThreadId;
  }

  Future<void> _createThread() async {
    if (_uid == null || _creating) return;
    setState(() => _creating = true);
    try {
      final id = await SupabaseService.client.rpc('create_support_thread', params: {'p_title': 'دعم الفائق'});
      if (mounted) setState(() => _threadId = id.toString());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر فتح محادثة الدعم: $e')));
    } finally { if (mounted) setState(() => _creating = false); }
  }

  Future<void> _send() async {
    final text = _message.text.trim(); final thread = _threadId;
    if (text.isEmpty || thread == null || _sending) return;
    setState(() => _sending = true);
    try {
      await SupabaseService.client.rpc('send_chat_message', params: {'p_thread_id': thread, 'p_body': text});
      _message.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إرسال الرسالة: $e')));
    } finally { if (mounted) setState(() => _sending = false); }
  }

  Stream<List<Map<String, dynamic>>> _threads() =>
      SupabaseService.client.from('chat_threads').stream(primaryKey: ['id']).order('created_at', ascending: false);

  Stream<List<Map<String, dynamic>>> _messages(String id) =>
      SupabaseService.client.from('chat_messages').stream(primaryKey: ['id']).eq('thread_id', id).order('created_at', ascending: true);

  @override Widget build(BuildContext context) {
    if (_uid == null) return const Scaffold(body: Center(child: Text('يجب تسجيل الدخول أولاً.')));
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(
      appBar: AppBar(title: const Text('دعم الفائق', style: TextStyle(fontWeight: FontWeight.w900))),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _threads(),
        builder: (context, threads) {
          if (threads.hasError) return Center(child: Text('تعذر تحميل محادثات الدعم: ' + threads.error.toString()));
          final rows = threads.data ?? const <Map<String, dynamic>>[];
          final selected = _threadId ?? (rows.isNotEmpty ? rows.first['id']?.toString() : null);
          if (_threadId == null && selected != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _threadId == null) setState(() => _threadId = selected);
            });
          }
          return Column(children: [
            if (rows.isNotEmpty) SizedBox(
              height: 58,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                scrollDirection: Axis.horizontal,
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final id = rows[i]['id'].toString();
                  return ChoiceChip(
                    label: Text((rows[i]['title'] ?? 'دعم').toString()),
                    selected: id == selected,
                    onSelected: (_) => setState(() => _threadId = id),
                  );
                },
              ),
            ),
            Expanded(
              child: selected == null
                  ? Center(child: FilledButton.icon(
                      onPressed: _creating ? null : _createThread,
                      icon: const Icon(Icons.support_agent_outlined),
                      label: Text(_creating ? 'جاري فتح المحادثة...' : 'فتح محادثة مع دعم الفائق'),
                    ))
                  : StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _messages(selected),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) return Center(child: Text('تعذر تحميل الرسائل: ' + snapshot.error.toString()));
                        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                        final messages = snapshot.data ?? const <Map<String, dynamic>>[];
                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                          itemCount: messages.length,
                          itemBuilder: (_, i) {
                            final row = messages[i];
                            final mine = row['sender_id']?.toString() == _uid;
                            return Align(
                              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 320),
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: mine ? Theme.of(context).colorScheme.primaryContainer : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text((row['body'] ?? '').toString()),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
            if (selected != null) SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                child: Row(children: [
                  Expanded(child: TextField(
                    controller: _message,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(hintText: 'اكتب رسالتك للدعم...', border: OutlineInputBorder()),
                  )),
                  const SizedBox(width: 8),
                  IconButton.filled(onPressed: _sending ? null : _send, icon: const Icon(Icons.send)),
                ]),
              ),
            ),
          ]);
        },
      ),
    ));
  }

  @override void dispose() { _message.dispose(); super.dispose(); }
}
