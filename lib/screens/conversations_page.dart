import 'dart:async';

import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import 'ai_assistant_page.dart';
import 'group_chat_page.dart';
import 'support_chat_page.dart';

/// WeChat-style "Chats" tab: a unified conversation list where the first entry
/// is the always-available Alfaeq AI, followed by live support/group threads.
/// Threads update live (Realtime) and show an unread badge per conversation.
class ConversationsPage extends StatefulWidget {
  const ConversationsPage({super.key});
  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage> {
  String? get _uid => SupabaseService.client.auth.currentUser?.id;

  Timer? _unreadTimer;
  Map<String, int> _unread = {};

  @override
  void initState() {
    super.initState();
    _refreshUnread();
    // Realtime pushes message rows, but the unread aggregate is cheap to poll;
    // a short interval keeps the badge fresh without a second subscription.
    _unreadTimer = Timer.periodic(const Duration(seconds: 15), (_) => _refreshUnread());
  }

  @override
  void dispose() {
    _unreadTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshUnread() async {
    if (_uid == null || !SupabaseService.isInitialized) return;
    try {
      final res = await SupabaseService.client.rpc('my_thread_unread_counts');
      final counts = <String, int>{};
      for (final row in (res as List)) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = map['thread_id']?.toString();
        final value = map['unread'];
        if (id != null && value is num && value > 0) counts[id] = value.toInt();
      }
      if (mounted) setState(() => _unread = counts);
    } catch (_) {/* unread badges are best-effort */}
  }

  Stream<List<Map<String, dynamic>>> _threads() => SupabaseService.client
      .from('chat_threads')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false);

  Stream<List<Map<String, dynamic>>> _lastMessage(String threadId) =>
      SupabaseService.client
          .from('chat_messages')
          .stream(primaryKey: ['id'])
          .eq('thread_id', threadId)
          .order('created_at', ascending: false)
          .limit(1);

  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return const Scaffold(body: Center(child: Text('يجب تسجيل الدخول أولاً.')));
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المحادثات', style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            IconButton(
              tooltip: 'مجموعة جديدة',
              icon: const Icon(Icons.group_add_outlined),
              onPressed: () async {
                final id = await showCreateGroupSheet(context);
                if (id != null && context.mounted) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => GroupChatPage(threadId: id, title: 'مجموعة جديدة')));
                }
              },
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _AiConversationTile(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AiAssistantPage()),
              ),
            ),
            const Divider(height: 1),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: _threads(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('تعذر تحميل المحادثات: ${snapshot.error}'),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final rows = snapshot.data ?? const <Map<String, dynamic>>[];
                if (rows.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('لا توجد محادثات بعد. ابدأ مع ذكاء الفائق أو دعم الفائق.'),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final row in rows)
                      _ThreadTile(row: row, lastMessage: _lastMessage, unread: _unread[row['id'].toString()] ?? 0),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AiConversationTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AiConversationTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: primary,
        child: const Icon(Icons.auto_awesome, color: Colors.white, size: 26),
      ),
      title: const Text('ذكاء الفائق', style: TextStyle(fontWeight: FontWeight.w900)),
      subtitle: const Text('مساعدك الذكي: بحث، طلبات، سلة، ومحفظة', maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_left),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  final Map<String, dynamic> row;
  final Stream<List<Map<String, dynamic>>> Function(String) lastMessage;
  final int unread;
  const _ThreadTile({required this.row, required this.lastMessage, this.unread = 0});

  @override
  Widget build(BuildContext context) {
    final id = row['id'].toString();
    final title = (row['title'] ?? 'محادثة').toString();
    final type = (row['thread_type'] ?? '').toString();
    final isGroup = type == 'group';
    final isSupport = type == 'support' || title.contains('دعم');
    return Column(
      children: [
        ListTile(
          onTap: () async {
            try { await SupabaseService.client.rpc('mark_thread_read', params: {'p_thread_id': id}); } catch (_) {}
            if (!context.mounted) return;
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => isGroup
                    ? GroupChatPage(threadId: id, title: title)
                    : SupportChatPage(initialThreadId: id),
              ),
            );
          },
          leading: CircleAvatar(
            radius: 26,
            backgroundColor: const Color(0xFFF1F6FF),
            child: Icon(isGroup ? Icons.groups_outlined : isSupport ? Icons.support_agent_outlined : Icons.forum_outlined, color: const Color(0xFF0B63CE)),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: StreamBuilder<List<Map<String, dynamic>>>(
            stream: lastMessage(id),
            builder: (context, snapshot) {
              final msgs = snapshot.data ?? const <Map<String, dynamic>>[];
              final text = msgs.isEmpty ? 'لا رسائل بعد' : (msgs.first['body'] ?? '').toString();
              return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
            },
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (unread > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                  child: Text(unread > 99 ? '99+' : '$unread', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                ),
              const Icon(Icons.chevron_left),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}
