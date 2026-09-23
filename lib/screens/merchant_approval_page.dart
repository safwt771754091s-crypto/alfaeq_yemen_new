import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';

class MerchantApprovalPage extends StatefulWidget {
  const MerchantApprovalPage({super.key});
  @override
  State<MerchantApprovalPage> createState() => _MerchantApprovalPageState();
}

class _MerchantApprovalPageState extends State<MerchantApprovalPage> {
  final _auth = AuthService();
  bool _busy = false;
  late Future<List<Map<String, dynamic>>> _pending;

  @override
  void initState() {
    super.initState();
    _pending = _loadPending();
  }

  Future<bool> _isStaff() async {
    final claims = await _auth.claims();
    return claims['admin'] == true ||
        claims['owner'] == true ||
        claims['app_role'] == 'admin' ||
        claims['app_role'] == 'owner' ||
        claims['role'] == 'admin' ||
        claims['role'] == 'owner';
  }

  Future<List<Map<String, dynamic>>> _loadPending() async {
    if (!SupabaseService.isInitialized || !await _isStaff()) return [];
    final rows = await SupabaseService.client
        .from('stores')
        .select()
        .eq('status', 'pending')
        .order('created_at', ascending: true)
        .limit(100);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _setStatus(Map<String, dynamic> store, String status) async {
    final user = const AuthService().currentUser;
    if (user == null || !await _isStaff()) {
      _message('غير مصرح لك بإدارة اعتماد المتاجر.');
      return;
    }
    if (!SupabaseService.isInitialized) {
      _message('قاعدة بيانات الإنتاج غير متاحة.');
      return;
    }

    setState(() => _busy = true);
    try {
      final storeId = '';
      await SupabaseService.client.from('stores').update({
        'status': status,
        'reviewed_by': user.uid,
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', storeId).eq('status', 'pending');

      await SupabaseService.client.from('audit_logs').insert({
        'actor_uid': user.uid,
        'email': user.email,
        'action': 'merchant_store_${status == 'approved' ? 'approved' : 'rejected'}',
        'result': 'success',
        'source': 'admin_merchant_approval',
        'details': {
          'store_id': storeId,
          'store_name': store['name'],
          'owner_id': store['owner_id'],
          'status': status,
        },
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      _message(status == 'approved' ? 'تم اعتماد المتجر وأصبح مؤهلاً للظهور للعملاء.' : 'تم رفض المتجر.');
      if (mounted) setState(() => _pending = _loadPending());
    } catch (e) {
      _message('تعذر تحديث حالة المتجر: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('اعتماد المتاجر')),
        body: FutureBuilder<bool>(
          future: _isStaff(),
          builder: (context, access) {
            if (access.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (access.data != true) return const Center(child: Text('هذه الصفحة مخصصة للإدارة المعتمدة فقط.'));
            return FutureBuilder<List<Map<String, dynamic>>>(
              future: _pending,
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('تعذر تحميل طلبات الاعتماد.\n${snapshot.error}')));
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                final stores = snapshot.data ?? const <Map<String, dynamic>>[];
                if (stores.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('لا توجد متاجر بانتظار الاعتماد.')));
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: stores.length,
                  itemBuilder: (context, index) {
                    final data = stores[index];
                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            const CircleAvatar(child: Icon(Icons.storefront_outlined)),
                            const SizedBox(width: 12),
                            Expanded(child: Text('${data['name'] ?? 'متجر'}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                            const Chip(label: Text('قيد المراجعة')),
                          ]),
                          const SizedBox(height: 12),
                          Text('الهاتف: ${data['phone'] ?? '—'}'),
                          Text('العنوان: ${data['address'] ?? '—'}'),
                          Text('القسم: ${data['section_id'] ?? '—'}'),
                          Text('صاحب المتجر: ${data['owner_id'] ?? '—'}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          const SizedBox(height: 14),
                          Row(children: [
                            Expanded(child: FilledButton.icon(onPressed: _busy ? null : () => _setStatus(data, 'approved'), icon: const Icon(Icons.verified), label: const Text('اعتماد'))),
                            const SizedBox(width: 10),
                            Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : () => _setStatus(data, 'rejected'), icon: const Icon(Icons.block), label: const Text('رفض'))),
                          ]),
                        ]),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
