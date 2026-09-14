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
    'owner': 'مالك المنصة',
    'admin': 'مدير',
    'developer': 'مطور',
    'finance': 'مالية',
    'merchant': 'تاجر',
    'driver': 'مندوب',
    'customer': 'عميل',
  };

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final callable = _functions.httpsCallable('listManagedUsers');
      final result = await callable.call();
      final data = Map<String, dynamic>.from(result.data as Map);
      final raw = (data['users'] as List? ?? const []);
      final users = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message ?? e.code;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _setRole(Map<String, dynamic> user, String role) async {
    final uid = user['uid'] as String?;
    if (uid == null) return;
    try {
      await _functions.httpsCallable('setManagedUserRole').call({'uid': uid, 'role': role});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تغيير الدور إلى ${roles[role]}، وسيظهر بعد تحديث جلسة المستخدم.')),
      );
      await _loadUsers();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
    }
  }

  Future<void> _setDisabled(Map<String, dynamic> user, bool disabled) async {
    final uid = user['uid'] as String?;
    if (uid == null) return;
    try {
      await _functions.httpsCallable('setManagedUserDisabled').call({'uid': uid, 'disabled': disabled});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(disabled ? 'تم تعطيل المستخدم.' : 'تم تفعيل المستخدم.')),
      );
      await _loadUsers();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
    }
  }

  Future<void> _revokeSessions(Map<String, dynamic> user) async {
    final uid = user['uid'] as String?;
    if (uid == null) return;
    try {
      await _functions.httpsCallable('revokeManagedUserSessions').call({'uid': uid});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إلغاء جلسات المستخدم.')));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
    }
  }

  List<Map<String, dynamic>> get _visibleUsers {
    final query = _filter.trim().toLowerCase();
    if (query.isEmpty) return _users;
    return _users.where((u) {
      final text = '${u['email'] ?? ''} ${u['displayName'] ?? ''} ${u['phoneNumber'] ?? ''} ${u['role'] ?? ''}'.toLowerCase();
      return text.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة المستخدمين والأدوار'),
          actions: [IconButton(onPressed: _loading ? null : _loadUsers, icon: const Icon(Icons.refresh))],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.admin_panel_settings),
                            SizedBox(width: 8),
                            Expanded(child: Text('صلاحيات server-side', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text('تغيير الدور يتم عبر Firebase Admin SDK وليس من التطبيق مباشرة. هذا يمنع المستخدم من منح نفسه صلاحيات إدارية.'),
                        const SizedBox(height: 12),
                        TextField(
                          onChanged: (v) => setState(() => _filter = v),
                          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث بالاسم أو البريد أو الهاتف أو الدور', border: OutlineInputBorder()),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Card(child: ListTile(leading: const Icon(Icons.error_outline), title: const Text('تعذر تحميل المستخدمين'), subtitle: Text(_error!))),
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _loadUsers,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: _visibleUsers.length,
                        itemBuilder: (context, index) => _userCard(_visibleUsers[index]),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _userCard(Map<String, dynamic> user) {
    final role = user['role'] as String? ?? '';
    final disabled = user['disabled'] == true;
    final name = (user['displayName'] as String? ?? '').trim();
    final email = user['email'] as String? ?? '';
    final phone = user['phoneNumber'] as String? ?? '';
    final title = name.isEmpty ? (email.isEmpty ? phone : email) : name;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text(title.isEmpty ? '?' : title.substring(0, 1).toUpperCase())),
              title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${roles[role] ?? 'بدون دور'} • ${disabled ? 'معطل' : 'نشط'}'),
              trailing: PopupMenuButton<String>(
                onSelected: (action) {
                  if (action == 'disable') _setDisabled(user, true);
                  if (action == 'enable') _setDisabled(user, false);
                  if (action == 'revoke') _revokeSessions(user);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: disabled ? 'enable' : 'disable', child: Text(disabled ? 'تفعيل الحساب' : 'تعطيل الحساب')),
                  const PopupMenuItem(value: 'revoke', child: Text('إلغاء الجلسات الحالية')),
                ],
              ),
            ),
            DropdownButtonFormField<String>(
              value: roles.containsKey(role) ? role : null,
              decoration: const InputDecoration(labelText: 'الدور', border: OutlineInputBorder()),
              items: roles.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: (value) {
                if (value != null && value != role) _setRole(user, value);
              },
            ),
            if (email.isNotEmpty || phone.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text([email, phone].where((e) => e.isNotEmpty).join(' • '), style: Theme.of(context).textTheme.bodySmall),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
