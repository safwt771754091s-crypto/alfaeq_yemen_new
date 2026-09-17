import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'admin_user_management_page.dart';

/// مركز تشغيل المنصة.
///
/// يتيح للمالك تعيين حسابات موجودة كمدير أو مشرف من داخل المركز،
/// ثم إدارة صلاحيات كل حساب عبر مركز المستخدمين والصلاحيات.
class PlatformControlPage extends StatefulWidget {
  const PlatformControlPage({super.key});

  @override
  State<PlatformControlPage> createState() => _PlatformControlPageState();
}

class _PlatformControlPageState extends State<PlatformControlPage> {
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  bool _checkingOwner = true;
  bool _isOwner = false;

  static const _roleLabels = <String, String>{
    'admin': 'مدير',
    'supervisor': 'مشرف',
  };

  @override
  void initState() {
    super.initState();
    _checkOwner();
  }

  Future<void> _checkOwner() async {
    try {
      final result = await _functions.httpsCallable('listManagedUsers').call();
      // listManagedUsers is owner/admin gated; the backend remains the source of truth.
      final data = Map<String, dynamic>.from(result.data as Map);
      final current = data['currentUser'] is Map ? Map<String, dynamic>.from(data['currentUser'] as Map) : <String, dynamic>{};
      final role = current['role'];
      if (!mounted) return;
      setState(() {
        _isOwner = role == 'owner';
        _checkingOwner = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isOwner = false;
        _checkingOwner = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _loadUsers() async {
    final result = await _functions.httpsCallable('listManagedUsers').call();
    final data = Map<String, dynamic>.from(result.data as Map);
    final raw = data['users'] as List? ?? const [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _assignStaff() async {
    if (!_isOwner) return;
    try {
      final users = await _loadUsers();
      final candidates = users.where((u) => u['role'] != 'owner').toList();
      if (!mounted) return;

      Map<String, dynamic>? selectedUser;
      String selectedRole = 'admin';
      final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('إضافة مدير أو مشرف'),
            content: SizedBox(
              width: 520,
              child: candidates.isEmpty
                  ? const Text('لا توجد حسابات متاحة. أنشئ حساب المستفيد أولاً ثم عيّنه من هنا.')
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DropdownButtonFormField<Map<String, dynamic>>(
                            initialValue: selectedUser,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'الحساب',
                              border: OutlineInputBorder(),
                            ),
                            items: candidates.map((user) {
                              final name = (user['displayName'] ?? user['name'] ?? '').toString().trim();
                              final email = (user['email'] ?? '').toString().trim();
                              final phone = (user['phoneNumber'] ?? '').toString().trim();
                              final label = [name, email, phone].where((v) => v.isNotEmpty).join(' • ');
                              return DropdownMenuItem<Map<String, dynamic>>(
                                value: user,
                                child: Text(label.isEmpty ? 'حساب بدون بيانات' : label, overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (value) => setDialogState(() => selectedUser = value),
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: selectedRole,
                            decoration: const InputDecoration(
                              labelText: 'الدور التشغيلي',
                              border: OutlineInputBorder(),
                            ),
                            items: _roleLabels.entries.map((entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            )).toList(),
                            onChanged: (value) => setDialogState(() => selectedRole = value ?? 'admin'),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'بعد التعيين تُحفظ الصلاحيات الحقيقية على Firebase Custom Claims. يمكنك تحديد الصلاحيات التفصيلية مباشرة من إدارة الحسابات.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
              FilledButton.icon(
                onPressed: selectedUser == null
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: Text('تعيين ${_roleLabels[selectedRole]}'),
              ),
            ],
          ),
        ),
      );

      if (result != true || selectedUser == null) return;
      final uid = selectedUser!['uid']?.toString();
      if (uid == null || uid.isEmpty) return;
      await _functions.httpsCallable('setManagedUserRole').call({'uid': uid, 'role': selectedRole});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تعيين الحساب كـ ${_roleLabels[selectedRole]} بنجاح.')),
      );
      await _checkOwner();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تنفيذ العملية: $e')));
    }
  }

  void _openUserManagement() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminUserManagementPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('مركز تشغيل المنصة')),
        body: _checkingOwner
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.settings_suggest_outlined)),
                      title: const Text('مركز التحكم', style: TextStyle(fontWeight: FontWeight.w900)),
                      subtitle: const Text('إدارة تشغيل المنصة من مكان واحد مع فرض الصلاحيات على الخادم.'),
                    ),
                  ),
                  if (_isOwner) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(children: [
                              Icon(Icons.admin_panel_settings_outlined),
                              SizedBox(width: 8),
                              Expanded(child: Text('صلاحيات المالك التشغيلية', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                            ]),
                            const SizedBox(height: 8),
                            const Text('من هنا يستطيع المالك تعيين حساب مسجل كمدير أو مشرف، ثم منحه الصلاحيات المناسبة مثل التجار والمنتجات والمحافظ والأتمتة والتوزيع ومركز المطور.'),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.icon(onPressed: _assignStaff, icon: const Icon(Icons.person_add_alt_1), label: const Text('إضافة مدير أو مشرف')),
                                OutlinedButton.icon(onPressed: _openUserManagement, icon: const Icon(Icons.manage_accounts_outlined), label: const Text('إدارة الصلاحيات التفصيلية')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.category_outlined),
                      title: Text('الأقسام'),
                      subtitle: Text('إدارة الأقسام الديناميكية من مركز التشغيل.'),
                    ),
                  ),
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.account_balance_wallet_outlined),
                      title: Text('الدفع والمحافظ'),
                      subtitle: Text('إدارة قنوات الدفع وحالة إعدادها، مع صلاحية المحافظ للجهات المخولة.'),
                    ),
                  ),
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.storefront_outlined),
                      title: Text('التجار'),
                      subtitle: Text('إدارة التجار والمتاجر مع الحفاظ على الملكية والصلاحيات.'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
