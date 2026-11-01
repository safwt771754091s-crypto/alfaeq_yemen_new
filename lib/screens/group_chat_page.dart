import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../widgets/chat_reaction_bar.dart';
import '../widgets/chat_transfer_bubble.dart';
import '../widgets/emoji_picker.dart';
import 'group_qr_page.dart';
import 'red_packet_page.dart';
import 'send_red_packet_sheet.dart';
import 'send_transfer_sheet.dart';

/// WeChat-style group conversation: message stream, composer, and an
/// "add members" sheet that lists the caller's chat contacts.
///
/// Also serves 1:1 threads when a [peerUid] is supplied, in which case the
/// composer offers a "transfer money" button next to the red packet.
class GroupChatPage extends StatefulWidget {
  final String threadId;
  final String title;
  final String? peerUid;
  final String? peerName;
  const GroupChatPage({super.key, required this.threadId, required this.title, this.peerUid, this.peerName});
  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  final _message = TextEditingController();
  bool _sending = false;
  bool _showEmoji = false;
  String? get _uid => SupabaseService.client.auth.currentUser?.id;

  /// Live reactions for this thread, keyed by message id.
  Stream<List<Map<String, dynamic>>> _reactions() => SupabaseService.client
      .from('message_reactions')
      .stream(primaryKey: ['id'])
      .eq('thread_id', widget.threadId);

  Future<void> _toggleReaction(String messageId, String emoji) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final existing = await SupabaseService.client
          .from('message_reactions')
          .select('id')
          .eq('message_id', messageId)
          .eq('user_id', uid)
          .eq('emoji', emoji)
          .limit(1);
      if (existing.isNotEmpty) {
        await SupabaseService.client.from('message_reactions').delete().eq('id', existing.first['id']);
      } else {
        await SupabaseService.client.from('message_reactions').insert({
          'message_id': messageId,
          'user_id': uid,
          'emoji': emoji,
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحديث التفاعل: $e')));
    }
  }

  Future<void> _pickReaction(String messageId) async {
    const quick = ['👍', '❤️', '😂', '😮', '😢', '🙏', '🔥', '🎉'];
    final emoji = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                for (final e in quick)
                  InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => Navigator.pop(context, e),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F7FA),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 28)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (emoji != null) await _toggleReaction(messageId, emoji);
  }

  void _insertEmoji(String emoji) {
    final text = _message.text;
    final selection = _message.selection;
    final offset = selection.isValid ? selection.start : text.length;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    _message.value = TextEditingValue(
      text: text.replaceRange(start, end, emoji),
      selection: TextSelection.collapsed(offset: offset + emoji.length),
    );
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await SupabaseService.client.rpc('send_chat_message', params: {'p_thread_id': widget.threadId, 'p_body': text});
      _message.clear();
      if (_showEmoji) setState(() => _showEmoji = false);
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
            if (widget.peerUid == null)
              IconButton(
                tooltip: 'رمز المجموعة',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => GroupQrPage(threadId: widget.threadId, title: widget.title)),
                ),
                icon: const Icon(Icons.qr_code_2),
              ),
            IconButton(onPressed: _addMembers, tooltip: 'إضافة أعضاء', icon: const Icon(Icons.person_add_alt_1_outlined)),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _reactions(),
                builder: (context, reactionsSnapshot) {
                  final allReactions = reactionsSnapshot.data ?? const <Map<String, dynamic>>[];
                  return StreamBuilder<List<Map<String, dynamic>>>(
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
                          final messageId = row['id'].toString();
                          final mine = row['sender_id']?.toString() == _uid;
                          final sender = (row['metadata'] is Map ? (row['metadata'] as Map)['sender_name'] : null)?.toString();
                          final meta = row['metadata'];
                          final reactions = allReactions.where((r) => r['message_id']?.toString() == messageId).toList();
                          final reactionBar = ChatReactionBar(
                            reactions: reactions,
                            myUid: _uid,
                            onToggle: (emoji) => _toggleReaction(messageId, emoji),
                            onAdd: () => _pickReaction(messageId),
                          );
                          if (meta is Map && meta['kind'] == 'transfer') {
                            return Column(
                              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              children: [
                                ChatTransferBubble(meta: meta, mine: mine),
                                Padding(
                                  padding: EdgeInsets.only(left: mine ? 0 : 4, right: mine ? 4 : 0),
                                  child: reactionBar,
                                ),
                              ],
                            );
                          }
                          final packetId = meta is Map ? meta['packet_id']?.toString() : null;
                          if (packetId != null) {
                            return Column(
                              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              children: [
                                Align(
                                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                                  child: GestureDetector(
                                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RedPacketPage(packetId: packetId, title: 'الحزمة الحمراء 🧧'))),
                                    child: Container(
                                      constraints: const BoxConstraints(maxWidth: 300),
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(colors: [Color(0xFFE67E22), Color(0xFFC0392B)]),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Row(children: [
                                        const Icon(Icons.card_giftcard, color: Colors.white, size: 30),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Text((row['body'] ?? 'حزمة حمراء 🧧').toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                                            const SizedBox(height: 2),
                                            Text('${meta is Map ? meta['amount'] ?? '' : ''} ${meta is Map ? meta['currency'] ?? '' : ''} • اضغط للفتح', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                          ]),
                                        ),
                                      ]),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.only(left: mine ? 0 : 4, right: mine ? 4 : 0),
                                  child: reactionBar,
                                ),
                              ],
                            );
                          }
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
                                GestureDetector(
                                  onLongPress: () => _pickReaction(messageId),
                                  child: Container(
                                    constraints: const BoxConstraints(maxWidth: 320),
                                    margin: const EdgeInsets.only(bottom: 2),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: mine ? Theme.of(context).colorScheme.primaryContainer : Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Text((row['body'] ?? '').toString()),
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.only(left: mine ? 0 : 4, right: mine ? 4 : 0),
                                  child: reactionBar,
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
            if (_showEmoji) EmojiPicker(onEmoji: _insertEmoji),
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
                  IconButton(
                    tooltip: 'إيموجي',
                    onPressed: () => setState(() => _showEmoji = !_showEmoji),
                    icon: Icon(_showEmoji ? Icons.keyboard : Icons.emoji_emotions_outlined,
                        color: _showEmoji ? const Color(0xFF07C160) : null),
                  ),
                  if (widget.peerUid != null)
                    IconButton(
                      tooltip: 'تحويل مبلغ',
                      onPressed: () async {
                        final sent = await showSendTransferSheet(
                          context,
                          threadId: widget.threadId,
                          toUid: widget.peerUid!,
                          toName: widget.peerName ?? 'المستلم',
                        );
                        if (sent && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم التحويل ✅')));
                      },
                      icon: const Icon(Icons.send_to_mobile, color: Color(0xFF07C160)),
                    ),
                  IconButton(
                    tooltip: 'حزمة حمراء',
                    onPressed: () async {
                      final sent = await showSendRedPacketSheet(context, threadId: widget.threadId);
                      if (sent && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال الحزمة الحمراء 🧧')));
                    },
                    icon: const Icon(Icons.card_giftcard, color: Color(0xFFC0392B)),
                  ),
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
