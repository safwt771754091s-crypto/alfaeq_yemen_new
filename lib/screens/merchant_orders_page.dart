import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class MerchantOrdersPage extends StatefulWidget {
  const MerchantOrdersPage({super.key});

  @override
  State<MerchantOrdersPage> createState() => _MerchantOrdersPageState();
}

class _MerchantOrdersPageState extends State<MerchantOrdersPage> {
  final _auth = AuthService();
  bool _busy = false;

  Future<bool> _allowed() async {
    final role = await _auth.role();
    return role == 'merchant' || role == 'admin' || role == 'owner' || role == 'developer';
  }

  Future<void> _setStatus(QueryDocumentSnapshot<Map<String, dynamic>> doc, String status) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !await _allowed()) return;
    setState(() => _busy = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.update(doc.reference, {
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final audit = FirebaseFirestore.instance.collection('auditLogs').doc();
      batch.set(audit, {
        'actorUid': user.uid,
        'email': user.email,
        'role': await _auth.role(),
        'action': 'merchant_order_status_$status',
        'result': 'success',
        'source': 'merchant_orders',
        'details': {'orderId': doc.id, 'status': status},
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      _message('تم تحديث حالة الطلب.');
    } on FirebaseException catch (e) {
      _message('تعذر تحديث الطلب: ${e.message ?? e.code}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: FutureBuilder<bool>(
        future: _allowed(),
        builder: (context, access) {
          if (access.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (access.data != true) {
            return const Scaffold(body: Center(child: Padding(padding: EdgeInsets.all(24), child: Text('مركز الطلبات مخصص للحسابات التجارية المعتمدة.'))));
          }
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) return const Scaffold(body: Center(child: Text('يجب تسجيل الدخول.')));
          return Scaffold(
            appBar: AppBar(title: const Text('طلبات التاجر')),
            body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('orders').where('merchantIds', arrayContains: user.uid).limit(100).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('تعذر تحميل الطلبات.\n${snapshot.error}')));
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                final docs = [...(snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>{})];
                docs.sort((a, b) => _time(b.data()['createdAt']).compareTo(_time(a.data()['createdAt'])));
                if (docs.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('لا توجد طلبات مرتبطة بمتجرك حالياً.')));
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) => _OrderCard(doc: docs[index], busy: _busy, onStatus: _setStatus),
                );
              },
            ),
          );
        },
      ),
    );
  }

  static DateTime _time(dynamic value) => value is Timestamp ? value.toDate() : DateTime.fromMillisecondsSinceEpoch(0);

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _OrderCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool busy;
  final Future<void> Function(QueryDocumentSnapshot<Map<String, dynamic>>, String) onStatus;

  const _OrderCard({required this.doc, required this.busy, required this.onStatus});

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final items = data['items'] is List ? (data['items'] as List) : const [];
    final status = '${data['status'] ?? 'pending'}';
    final delivery = '${data['deliveryStatus'] ?? 'awaiting_assignment'}';
    final total = data['total'];
    final currency = '${data['currency'] ?? 'YER'}';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(child: Icon(_statusIcon(status))),
        title: Text('طلب #${doc.id.substring(0, doc.id.length > 8 ? 8 : doc.id.length)}', style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('$status • $delivery'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('الإجمالي: ${total ?? 0} $currency', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              Text('عدد الأصناف: ${items.length}'),
              Text('العنوان: ${data['address'] ?? '—'}'),
              Text('الدفع: ${data['paymentMethod'] ?? '—'}'),
              const SizedBox(height: 10),
              ...items.whereType<Map>().map((item) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${item['name'] ?? 'صنف'}'),
                    subtitle: Text('الكمية: ${item['quantity'] ?? 0}'),
                    trailing: Text('${item['lineTotal'] ?? item['price'] ?? 0}'),
                  )),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (status == 'pending') FilledButton.icon(onPressed: busy ? null : () => onStatus(doc, 'accepted'), icon: const Icon(Icons.check), label: const Text('قبول')),
                if (status == 'accepted') FilledButton.icon(onPressed: busy ? null : () => onStatus(doc, 'preparing'), icon: const Icon(Icons.inventory_2_outlined), label: const Text('بدء التجهيز')),
                if (status == 'preparing') FilledButton.icon(onPressed: busy ? null : () => onStatus(doc, 'ready_for_pickup'), icon: const Icon(Icons.local_shipping_outlined), label: const Text('جاهز للاستلام')),
                if (status == 'pending' || status == 'accepted') OutlinedButton.icon(onPressed: busy ? null : () => onStatus(doc, 'cancelled'), icon: const Icon(Icons.close), label: const Text('إلغاء')),
              ]),
            ]),
          ),
        ],
      ),
    );
  }

  static IconData _statusIcon(String status) {
    switch (status) {
      case 'accepted': return Icons.check_circle_outline;
      case 'preparing': return Icons.inventory_2_outlined;
      case 'ready_for_pickup': return Icons.local_shipping_outlined;
      case 'cancelled': return Icons.cancel_outlined;
      default: return Icons.pending_actions_outlined;
    }
  }
}
