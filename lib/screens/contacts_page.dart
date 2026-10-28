import 'package:flutter/material.dart';

import '../services/chat_transfer_service.dart';
import '../services/supabase_service.dart';
import '../widgets/chat_transfer_bubble.dart';
import 'group_chat_page.dart';
import 'red_packet_page.dart';
import 'send_red_packet_sheet.dart';
import 'send_transfer_sheet.dart';

const _blue = Color(0xFF0D6EFD);
const _surface = Color(0xFFF5F7FA);

/// WeChat-style "Contacts" tab: saved contacts, my groups, and a directory of
/// people you already share a conversation with. Tapping a contact opens a
/// private one-to-one chat.
class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});
  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  String? get _uid => SupabaseService.client.auth.currentUser?.id;

  Future<void> _startChat(String uid, String name) async {
    try {
      final res = await SupabaseService.client.rpc('start_direct_thread', params: {'p_peer_uid': uid});
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => DirectChatPage(threadId: res.toString(), title: name)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر فتح المحادثة: $e')));
    }
  }

  Future<void> _saveContact(String uid, String name) async {
    final me = _uid;
    if (me == null) return;
    try {
      await SupabaseService.client.from('user_contacts').insert({'owner_id': me, 'contact_id': uid});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت إضافة $name إلى جهات اتصالك.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إضافة جهة الاتصال: $e')));
    }
  }

  Future<void> _addByUid() async {
    final controller = TextEditingController();
    final uid = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة جهة اتصال'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'أدخل معرّف المستخدم (UID)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('إضافة')),
        ],
      ),
    );
    if (uid == null || uid.isEmpty || uid == _uid) return;
    try {
      final row = await SupabaseService.client.from('users').select('uid,name').eq('uid', uid).maybeSingle();
      if (row == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد مستخدم بهذا المعرّف.')));
        return;
      }
      await _saveContact(uid, (row['name'] ?? 'مستخدم الفائق').toString());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر البحث عن المستخدم: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) return const Scaffold(body: Center(child: Text('يجب تسجيل الدخول أولاً.')));
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _surface,
        appBar: AppBar(
          title: const Text('الجهات', style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            IconButton(tooltip: 'إضافة جهة اتصال', icon: const Icon(Icons.person_add_alt), onPressed: _addByUid),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _card([
              ListTile(
                leading: const _Avatar(icon: Icons.person_add_alt_1),
                title: const Text('جهة اتصال جديدة', style: TextStyle(fontWeight: FontWeight.w900)),
                subtitle: const Text('أضف مستخدمًا بمعرّفه'),
                trailing: const Icon(Icons.chevron_left),
                onTap: _addByUid,
              ),
            ]),
            _sectionTitle('جهات اتصالي'),
            _savedContacts(),
            _sectionTitle('مجموعاتي'),
            _myGroups(),
            _sectionTitle('أشخاص تعرفهم'),
            _directory(),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black54, fontSize: 13)),
      );

  Widget _card(List<Widget> rows) => Card(
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE3E8EF))),
        child: Column(children: rows),
      );

  Widget _savedContacts() => FutureBuilder<List<Map<String, dynamic>>>(
        future: _rpcList('my_saved_contacts'),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator()));
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) return const _Empty(text: 'لا توجد جهات اتصال محفوظة بعد.');
          return _card([
            for (final c in rows)
              ListTile(
                leading: const _Avatar(icon: Icons.person_outline),
                title: Text((c['name'] ?? 'مستخدم الفائق').toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => _startChat(c['uid'].toString(), (c['name'] ?? 'محادثة').toString()),
              ),
          ]);
        },
      );

  Widget _myGroups() => StreamBuilder<List<Map<String, dynamic>>>(
        stream: SupabaseService.client.from('chat_threads').stream(primaryKey: ['id']).order('created_at', ascending: false),
        builder: (context, snapshot) {
          final groups = (snapshot.data ?? const <Map<String, dynamic>>[])
              .where((row) => (row['thread_type'] ?? '') == 'group')
              .toList();
          if (groups.isEmpty) return const _Empty(text: 'لا توجد مجموعات بعد. أنشئ مجموعة من تبويب المحادثات.');
          return _card([
            for (final g in groups)
              ListTile(
                leading: const _Avatar(icon: Icons.groups_outlined),
                title: Text((g['title'] ?? 'مجموعة').toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GroupChatPage(threadId: g['id'].toString(), title: (g['title'] ?? 'مجموعة').toString()))),
              ),
          ]);
        },
      );

  Widget _directory() => FutureBuilder<List<Map<String, dynamic>>>(
        future: _rpcList('list_my_contacts'),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator()));
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) return const _Empty(text: 'شارك محادثة مع أحدهم ليظهروا هنا.');
          return _card([
            for (final c in rows)
              ListTile(
                leading: const _Avatar(icon: Icons.forum_outlined),
                title: Text((c['name'] ?? 'مستخدم الفائق').toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('تشارك معه محادثة'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(tooltip: 'إضافة', icon: const Icon(Icons.person_add_alt_1, size: 20), onPressed: () => _saveContact(c['uid'].toString(), (c['name'] ?? '').toString())),
                  IconButton(tooltip: 'محادثة', icon: const Icon(Icons.chat_bubble_outline, size: 20), onPressed: () => _startChat(c['uid'].toString(), (c['name'] ?? 'محادثة').toString())),
                ]),
              ),
          ]);
        },
      );

  Future<List<Map<String, dynamic>>> _rpcList(String fn) async {
    try {
      final res = await SupabaseService.client.rpc(fn);
      return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return const [];
    }
  }
}

class _Avatar extends StatelessWidget {
  final IconData icon;
  const _Avatar({required this.icon});
  @override
  Widget build(BuildContext context) => CircleAvatar(radius: 24, backgroundColor: const Color(0xFFF1F6FF), child: Icon(icon, color: _blue));
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty({required this.text});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE3E8EF))),
          child: Padding(padding: const EdgeInsets.all(18), child: Text(text, style: const TextStyle(color: Colors.black54))),
        ),
      );
}

/// Private one-to-one conversation opened from the Contacts tab.
class DirectChatPage extends StatefulWidget {
  final String threadId;
  final String title;
  const DirectChatPage({super.key, required this.threadId, required this.title});
  @override
  State<DirectChatPage> createState() => _DirectChatPageState();
}

class _DirectChatPageState extends State<DirectChatPage> {
  final _message = TextEditingController();
  bool _sending = false;
  ChatPeer? _peer;
  String? get _uid => SupabaseService.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _markRead();
    _loadPeer();
  }

  Future<void> _loadPeer() async {
    try {
      final peer = await const ChatTransferService().peer(widget.threadId);
      if (mounted) setState(() => _peer = peer);
    } catch (_) {/* transfer button simply stays hidden */}
  }

  Future<void> _markRead() async {
    try {
      await SupabaseService.client.rpc('mark_thread_read', params: {'p_thread_id': widget.threadId});
    } catch (_) {/* best-effort */}
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
        appBar: AppBar(title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w900))),
        body: Column(children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _messages(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('تعذر تحميل الرسائل: ${snapshot.error}'));
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                final messages = snapshot.data ?? const <Map<String, dynamic>>[];
                if (messages.isEmpty) return const Center(child: Text('لا رسائل بعد — ابدأ الحديث.', style: TextStyle(color: Colors.black54)));
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final row = messages[i];
                    final mine = row['sender_id']?.toString() == _uid;
                    final meta = row['metadata'];
                    if (meta is Map && meta['kind'] == 'transfer') {
                      return ChatTransferBubble(meta: meta, mine: mine);
                    }
                    final packetId = meta is Map ? meta['packet_id']?.toString() : null;
                    if (packetId != null) {
                      return Align(
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
                      );
                    }
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
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _message,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(hintText: 'اكتب رسالة...', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none)),
                  ),
                ),
                const SizedBox(width: 8),
                if (_peer != null)
                  IconButton(
                    tooltip: 'تحويل مبلغ',
                    onPressed: () async {
                      final sent = await showSendTransferSheet(
                        context,
                        threadId: widget.threadId,
                        toUid: _peer!.uid,
                        toName: _peer!.name,
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
        ]),
      ),
    );
  }
}
