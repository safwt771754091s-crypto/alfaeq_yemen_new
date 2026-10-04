import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import 'ai_assistant_page.dart';
import 'support_chat_page.dart';

/// WeChat-style "Chats" tab: a unified conversation list where the first entry
/// is the always-available Alfaeq AI, followed by live support threads.
class ConversationsPage extends StatefulWidget {
  const ConversationsPage({super.key});
  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage> {
  String? get _uid => SupabaseService.client.auth.currentUser?.id;

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
                    for (final row in rows) _ThreadTile(row: row, lastMessage: _lastMessage),
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
  const _ThreadTile({required this.row, required this.lastMessage});

  @override
  Widget build(BuildContext context) {
    final id = row['id'].toString();
    final title = (row['title'] ?? 'محادثة').toString();
    final type = (row['thread_type'] ?? '').toString();
    final isSupport = type == 'support' || title.contains('دعم');
    return Column(
      children: [
        ListTile(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SupportChatPage(initialThreadId: id)),
          ),
          leading: CircleAvatar(
            radius: 26,
            backgroundColor: const Color(0xFFF1F6FF),
            child: Icon(isSupport ? Icons.support_agent_outlined : Icons.forum_outlined, color: const Color(0xFF0B63CE)),
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
          trailing: const Icon(Icons.chevron_left),
        ),
        const Divider(height: 1),
      ],
    );
  }
}
