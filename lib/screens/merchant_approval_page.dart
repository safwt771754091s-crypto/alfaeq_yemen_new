import 'package:supabase_flutter/supabase_flutter.dart';
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

  Future<bool> _isStaff() async {
    final claims = await _auth.claims();
    if (claims['admin'] == true || claims['owner'] == true) return true;
    final role = claims['role'];
    return role == 'admin' || role == 'owner';
  }

  Future<void> _setStatus(Map<String, dynamic> doc, String status) async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null || !await _isStaff()) {
      _message('غير مصرح لك بإدارة اعتماد المتاجر.');
      return;
    }

    setState(() => _busy = true);
    try {
      final data = doc;
      final reviewerRole = await _auth.role();
      await SupabaseService.client.from('stores').update({
        'status': status,
        'reviewed_by': user.id,
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', doc['id']);
      await SupabaseService.client.from('audit_logs').insert({
        'id': user.id + '-' + DateTime.now().microsecondsSinceEpoch.toString(),
        'actor_uid': user.id,
        'email': user.email,
        'role': reviewerRole,
        'action': 'merchant_store_${status == 'approved' ? 'approved' : 'rejected'}',
        'result': 'success',
        'source': 'admin_merchant_approval',
        'details': {
          'storeId': doc['id'],
          'storeName': data['name'],
          'ownerId': data['owner_id'],
          'status': status,
        },
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      _message(status == 'approved' ? 'تم اعتماد المتجر وأصبح مؤهلاً للظهور للعملاء.' : 'تم رفض المتجر.');
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
            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: SupabaseService.client.from('stores').stream(primaryKey: ['id']).eq('status', 'pending').limit(100),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('تعذر تحميل طلبات الاعتماد.\n${snapshot.error}')));
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                final docs = snapshot.data ?? const <Map<String, dynamic>>[];
                if (docs.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('لا توجد متاجر بانتظار الاعتماد.')));
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index];
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
                            Expanded(child: FilledButton.icon(onPressed: _busy ? null : () => _setStatus(doc, 'approved'), icon: const Icon(Icons.verified), label: const Text('اعتماد'))),
                            const SizedBox(width: 10),
                            Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : () => _setStatus(doc, 'rejected'), icon: const Icon(Icons.block), label: const Text('رفض'))),
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
