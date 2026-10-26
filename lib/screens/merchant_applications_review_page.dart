import 'package:flutter/material.dart';

import '../services/application_service.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';

/// Staff review queue for self-service merchant applications.
class MerchantApplicationsReviewPage extends StatefulWidget {
  const MerchantApplicationsReviewPage({super.key});

  @override
  State<MerchantApplicationsReviewPage> createState() => _MerchantApplicationsReviewPageState();
}

class _MerchantApplicationsReviewPageState extends State<MerchantApplicationsReviewPage> {
  final _auth = AuthService();
  final _svc = ApplicationService();
  bool _busy = false;

  Future<bool> _isStaff() async {
    final claims = await _auth.claims();
    if (claims['admin'] == true || claims['owner'] == true || claims['developer'] == true) return true;
    final role = claims['role'];
    return role == 'admin' || role == 'owner' || role == 'developer';
  }

  Future<void> _decide(Map<String, dynamic> doc, bool approve) async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null || !await _isStaff()) { _message('غير مصرح لك بمراجعة الطلبات.'); return; }
    String? notes;
    if (!approve) {
      notes = await _askReason();
      if (notes == null) return;
    }
    setState(() => _busy = true);
    try {
      await _svc.decideMerchantApplication(id: doc['id'].toString(), approve: approve, reviewNotes: notes);
      _message(approve ? 'تم اعتماد الطلب وتحويل الحساب إلى تاجر.' : 'تم رفض الطلب.');
    } catch (e) {
      _message('تعذر تحديث الطلب: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askReason() async {
    final c = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('سبب الرفض', style: TextStyle(fontWeight: FontWeight.w900)),
          content: TextField(controller: c, maxLines: 3, decoration: const InputDecoration(hintText: 'اكتب سبباً يظهر للمتقدم (اختياري)', border: OutlineInputBorder())),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('رفض')),
          ],
        ),
      ),
    );
    return result;
  }

  void _message(String t) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t))); }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('طلبات التجار')),
        body: FutureBuilder<bool>(
          future: _isStaff(),
          builder: (context, access) {
            if (access.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (access.data != true) return const Center(child: Text('هذه الصفحة مخصصة للإدارة المعتمدة فقط.'));
            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: _svc.pendingMerchantApplicationsStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('تعذر تحميل الطلبات.\n${snapshot.error}')));
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                final docs = snapshot.data ?? const <Map<String, dynamic>>[];
                if (docs.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('لا توجد طلبات تجار بانتظار المراجعة.')));
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            const CircleAvatar(child: Icon(Icons.storefront_outlined)),
                            const SizedBox(width: 12),
                            Expanded(child: Text('${d['store_name'] ?? 'متجر'}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                            const Chip(label: Text('قيد المراجعة')),
                          ]),
                          const SizedBox(height: 12),
                          Text('المتقدم: ${d['applicant_name'] ?? '—'}'),
                          Text('الهاتف: ${d['phone'] ?? '—'}'),
                          if (d['city'] != null && '${d['city']}'.isNotEmpty) Text('المدينة: ${d['city']}'),
                          if (d['address'] != null && '${d['address']}'.isNotEmpty) Text('العنوان: ${d['address']}'),
                          Text('القسم: ${d['section_id'] ?? '—'}'),
                          if (d['notes'] != null && '${d['notes']}'.isNotEmpty) Text('ملاحظات: ${d['notes']}', style: const TextStyle(color: Colors.black54)),
                          const SizedBox(height: 14),
                          Row(children: [
                            Expanded(child: FilledButton.icon(onPressed: _busy ? null : () => _decide(d, true), icon: const Icon(Icons.verified), label: const Text('اعتماد'))),
                            const SizedBox(width: 10),
                            Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : () => _decide(d, false), icon: const Icon(Icons.block), label: const Text('رفض'))),
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
