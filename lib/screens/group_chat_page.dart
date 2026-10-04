import 'package:flutter/material.dart';

import '../services/supabase_service.dart';

/// WeChat-style group conversation: message stream, composer, and an
/// "add members" sheet that lists the caller's chat contacts.
class GroupChatPage extends StatefulWidget {
  final String threadId;
  final String title;
  const GroupChatPage({super.key, required this.threadId, required this.title});
  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  final _message = TextEditingController();
  bool _sending = false;
  String? get _uid => SupabaseService.client.auth.currentUser?.id;

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

  Future<void> _addMembers() async {
    List<Map<String, dynamic>> contacts;
    try {
      final res = await SupabaseService.client.rpc('list_my_contacts');
      contacts = (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحميل جهات الاتصال: $e')));
      return;
    }
    if (!mounted) return;
    if (contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد جهات اتصال متاحة بعد. تظهر جهات الاتصال بعد مشاركة محادثة معهم.')));
      return;
    }
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ContactsSheet(contacts: contacts),
    );
    if (selected == null || selected.isEmpty) return;
    try {
      final added = await SupabaseService.client.rpc('add_group_members', params: {'p_thread_id': widget.threadId, 'p_member_uids': selected});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت إضافة $added عضوًا إلى المجموعة.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إضافة الأعضاء: $e')));
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
          actions: [
            IconButton(onPressed: _addMembers, tooltip: 'إضافة أعضاء', icon: const Icon(Icons.person_add_alt_1_outlined)),
          ],
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
                  if (messages.isEmpty) {
                    return const Center(child: Text('لا رسائل بعد. ابدأ المحادثة.', style: TextStyle(color: Colors.black54)));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: messages.length,
                    itemBuilder: (_, i) {
                      final row = messages[i];
                      final mine = row['sender_id']?.toString() == _uid;
                      final sender = (row['metadata'] is Map ? (row['metadata'] as Map)['sender_name'] : null)?.toString();
                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            if (!mine && sender != null && sender.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2, left: 4),
                                child: Text(sender, style: const TextStyle(fontSize: 11, color: Colors.black45)),
                              ),
                            Container(
                              constraints: const BoxConstraints(maxWidth: 320),
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: mine ? Theme.of(context).colorScheme.primaryContainer : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text((row['body'] ?? '').toString()),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _message,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(hintText: 'اكتب رسالة للمجموعة...', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(onPressed: _sending ? null : _send, icon: const Icon(Icons.send)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }
}

class _ContactsSheet extends StatefulWidget {
  final List<Map<String, dynamic>> contacts;
  const _ContactsSheet({required this.contacts});
  @override
  State<_ContactsSheet> createState() => _ContactsSheetState();
}

class _ContactsSheetState extends State<_ContactsSheet> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('إضافة أعضاء', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: widget.contacts.map((c) {
                    final uid = c['uid'].toString();
                    return CheckboxListTile(
                      value: _selected.contains(uid),
                      title: Text((c['name'] ?? 'مستخدم').toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                      onChanged: (v) => setState(() => v == true ? _selected.add(uid) : _selected.remove(uid)),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selected.isEmpty ? null : () => Navigator.pop(context, _selected.toList()),
                  child: Text('إضافة (${_selected.length})'),
                ),
              ),
            ],
          ),
        ),
      );
}

/// Bottom sheet used to create a new group and pick its first members.
Future<String?> showCreateGroupSheet(BuildContext context) async {
  final title = TextEditingController();
  final selected = <String>{};
  List<Map<String, dynamic>> contacts = [];
  try {
    final res = await SupabaseService.client.rpc('list_my_contacts');
    contacts = (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  } catch (_) {
    contacts = [];
  }
  if (!context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => Directionality(
      textDirection: TextDirection.rtl,
      child: StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('مجموعة جديدة', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              TextField(
                controller: title,
                decoration: const InputDecoration(hintText: 'اسم المجموعة', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              if (contacts.isNotEmpty)
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: contacts.map((c) {
                      final uid = c['uid'].toString();
                      return CheckboxListTile(
                        value: selected.contains(uid),
                        title: Text((c['name'] ?? 'مستخدم').toString()),
                        onChanged: (v) => setState(() => v == true ? selected.add(uid) : selected.remove(uid)),
                      );
                    }).toList(),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('لا توجد جهات اتصال بعد. يمكنك إنشاء المجموعة وإضافة الأعضاء لاحقًا.', style: TextStyle(color: Colors.black54)),
                ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    final name = title.text.trim();
                    if (name.isEmpty) return;
                    try {
                      final id = await SupabaseService.client.rpc('create_group_thread', params: {
                        'p_title': name,
                        'p_member_uids': selected.toList(),
                      });
                      if (context.mounted) Navigator.pop(context, id.toString());
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إنشاء المجموعة: $e')));
                      }
                    }
                  },
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('إنشاء المجموعة'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
