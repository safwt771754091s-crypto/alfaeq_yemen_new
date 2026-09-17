import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class AdminUserManagementPage extends StatefulWidget {
  const AdminUserManagementPage({super.key});
  @override
  State<AdminUserManagementPage> createState() => _AdminUserManagementPageState();
}

class _AdminUserManagementPageState extends State<AdminUserManagementPage> {
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String _filter = '';
  String? _error;

  static const roles = <String, String>{
    'owner': 'مالك المنصة', 'admin': 'مدير', 'supervisor': 'مشرف', 'developer': 'مطور',
    'finance': 'مالية', 'merchant': 'تاجر', 'driver': 'مندوب', 'customer': 'عميل',
  };
  static const permissionLabels = <String, String>{
    'manageMerchants': 'إضافة وإدارة التجار',
    'approveMerchants': 'اعتماد التجار',
    'manageProducts': 'إدارة الأصناف',
    'importProducts': 'استيراد/سحب الأصناف من Excel',
    'viewUsers': 'عرض الحسابات',
    'developerCenter': 'مركز المطور والأمن',
    'automation': 'أتمتة المنصة',
    'manageDispatch': 'إدارة المندوبين والتوزيع',
    'manageWallets': 'إدارة المحافظ',
  };

  @override
  void initState() { super.initState(); _loadUsers(); }

  Future<void> _loadUsers() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await _functions.httpsCallable('listManagedUsers').call();
      final data = Map<String, dynamic>.from(result.data as Map);
      final raw = (data['users'] as List? ?? const []);
      final users = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() { _users = users; _loading = false; });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.message ?? e.code; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _setRole(Map<String, dynamic> user, String role) async {
    final uid = user['uid'] as String?; if (uid == null) return;
    try {
      await _functions.httpsCallable('setManagedUserRole').call({'uid': uid, 'role': role});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تغيير الدور إلى ${roles[role]}')));
      await _loadUsers();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
    }
  }

  Future<void> _setPermissions(Map<String, dynamic> user) async {
    final uid = user['uid'] as String?; if (uid == null) return;
    final current = Set<String>.from((user['permissions'] as List? ?? const []).whereType<String>());
    final selected = Set<String>.from(current);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: Text('صلاحيات ${user['displayName'] ?? user['email'] ?? 'المشرف'}'),
        content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(children: permissionLabels.entries.map((entry) => CheckboxListTile(
          value: selected.contains(entry.key),
          title: Text(entry.value),
          dense: true,
          onChanged: (value) => setDialogState(() => value == true ? selected.add(entry.key) : selected.remove(entry.key)),
        )).toList()))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, selected), child: const Text('حفظ الصلاحيات'))],
      )),
    );
    if (result == null) return;
    try {
      await _functions.httpsCallable('setManagedUserPermissions').call({'uid': uid, 'permissions': result.toList()});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ صلاحيات الحساب على الخادم.')));
      await _loadUsers();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
    }
  }

  Future<void> _setDisabled(Map<String, dynamic> user, bool disabled) async {
    final uid = user['uid'] as String?; if (uid == null) return;
    try { await _functions.httpsCallable('setManagedUserDisabled').call({'uid': uid, 'disabled': disabled}); await _loadUsers(); }
    on FirebaseFunctionsException catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? e.code))); }
  }

  Future<void> _revokeSessions(Map<String, dynamic> user) async {
    final uid = user['uid'] as String?; if (uid == null) return;
    try { await _functions.httpsCallable('revokeManagedUserSessions').call({'uid': uid}); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إلغاء الجلسات الحالية.'))); }
    on FirebaseFunctionsException catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? e.code))); }
  }

  List<Map<String, dynamic>> get _visibleUsers {
    final query = _filter.trim().toLowerCase();
    if (query.isEmpty) return _users;
    return _users.where((u) => '${u['email'] ?? ''} ${u['displayName'] ?? ''} ${u['phoneNumber'] ?? ''} ${u['role'] ?? ''}'.toLowerCase().contains(query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final onlineCount = _users.where((u) => u['isOnline'] == true).length;
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(
      appBar: AppBar(title: const Text('حسابات المنصة'), actions: [IconButton(onPressed: _loading ? null : _loadUsers, icon: const Icon(Icons.refresh))]),
      body: _loading ? const Center(child: CircularProgressIndicator()) : Column(children: [
        Container(margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.admin_panel_settings), const SizedBox(width: 8), const Expanded(child: Text('إدارة الحسابات والصلاحيات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))), Chip(label: Text('$onlineCount متصل الآن'))]),
          const SizedBox(height: 8), const Text('المالك يستطيع تعيين مدير أو مشرف ثم تحديد الصلاحيات بشكل منفصل لكل حساب.'), const SizedBox(height: 12),
          TextField(onChanged: (v) => setState(() => _filter = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث بالاسم أو البريد أو الهاتف أو الدور', border: OutlineInputBorder())),
        ])),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Card(child: ListTile(leading: const Icon(Icons.error_outline), title: const Text('تعذر تحميل المستخدمين'), subtitle: Text(_error!)))),
        Expanded(child: RefreshIndicator(onRefresh: _loadUsers, child: ListView.builder(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), itemCount: _visibleUsers.length, itemBuilder: (context, index) => _userCard(_visibleUsers[index])))),
      ]),
    ));
  }

  Widget _userCard(Map<String, dynamic> user) {
    final role = user['role'] as String? ?? '';
    final disabled = user['disabled'] == true;
    final online = user['isOnline'] == true;
    final name = (user['displayName'] as String? ?? '').trim();
    final email = user['email'] as String? ?? '';
    final phone = user['phoneNumber'] as String? ?? '';
    final title = name.isEmpty ? (email.isEmpty ? phone : email) : name;
    final initial = title.isEmpty ? '?' : title.characters.first.toUpperCase();
    final canConfigure = role == 'admin' || role == 'supervisor';
    final permissions = List<String>.from((user['permissions'] as List? ?? const []).whereType<String>());
    return Card(margin: const EdgeInsets.only(bottom: 10), child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
      ListTile(contentPadding: EdgeInsets.zero, leading: Stack(children: [CircleAvatar(child: Text(initial)), if (online) Positioned(left: 0, bottom: 0, child: Container(width: 13, height: 13, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.green, border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2))))]),
        title: Row(children: [Expanded(child: Text(title.isEmpty ? 'حساب بدون اسم' : title, maxLines: 1, overflow: TextOverflow.ellipsis)), const SizedBox(width: 8), Text(online ? 'متصل الآن' : 'غير متصل', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: online ? Colors.green : Colors.grey))]),
        subtitle: Text('${roles[role] ?? 'بدون دور'} • ${disabled ? 'معطل' : 'نشط'}'),
        trailing: PopupMenuButton<String>(onSelected: (action) { if (action == 'disable') _setDisabled(user, true); if (action == 'enable') _setDisabled(user, false); if (action == 'revoke') _revokeSessions(user); if (action == 'permissions') _setPermissions(user); }, itemBuilder: (_) => [PopupMenuItem(value: disabled ? 'enable' : 'disable', child: Text(disabled ? 'تفعيل الحساب' : 'تعطيل الحساب')), const PopupMenuItem(value: 'revoke', child: Text('إلغاء الجلسات الحالية')), if (canConfigure) const PopupMenuItem(value: 'permissions', child: Text('تحديد الصلاحيات'))]),
      ),
      DropdownButtonFormField<String>(initialValue: roles.containsKey(role) ? role : null, decoration: const InputDecoration(labelText: 'الدور', border: OutlineInputBorder()), items: roles.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(), onChanged: (value) { if (value != null && value != role) _setRole(user, value); }),
      if (canConfigure) Padding(padding: const EdgeInsets.only(top: 8), child: Align(alignment: Alignment.centerRight, child: Wrap(spacing: 6, runSpacing: 4, children: [for (final p in permissions) Chip(label: Text(permissionLabels[p] ?? p)), ActionChip(avatar: const Icon(Icons.tune, size: 16), label: const Text('تعديل الصلاحيات'), onPressed: () => _setPermissions(user))]))),
      if (email.isNotEmpty || phone.isNotEmpty) Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.only(top: 8), child: Text([email, phone].where((e) => e.isNotEmpty).join(' • '), style: Theme.of(context).textTheme.bodySmall))),
      if (user['lastSeen'] != null) Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.only(top: 4), child: Text('آخر حضور: ${user['lastSeen']}', style: Theme.of(context).textTheme.bodySmall))),
    ])));
  }
}
