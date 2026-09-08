import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class SmartDispatchPage extends StatefulWidget {
  const SmartDispatchPage({super.key});

  @override
  State<SmartDispatchPage> createState() => _SmartDispatchPageState();
}

class _SmartDispatchPageState extends State<SmartDispatchPage> {
  final _auth = AuthService();
  bool _busy = false;

  Future<bool> _staff() async {
    final role = await _auth.role();
    return role == 'admin' || role == 'owner' || role == 'developer';
  }

  double _score(Map<String, dynamic> driver) {
    final approved = driver['approved'] == true;
    final online = driver['isOnline'] == true;
    final active = (driver['activeOrderCount'] as num?)?.toDouble() ?? 0;
    final rating = (driver['rating'] as num?)?.toDouble() ?? 5;
    var score = 0.0;
    if (approved) score += 50;
    if (online) score += 40;
    score += (10 - active).clamp(0, 10);
    score += rating.clamp(0, 5);
    if (driver['currentLocation'] is GeoPoint) score += 5;
    return score;
  }

  Future<void> _assign(
    QueryDocumentSnapshot<Map<String, dynamic>> order,
    QueryDocumentSnapshot<Map<String, dynamic>> driver,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !await _staff()) return;
    setState(() => _busy = true);
    try {
      final driverData = driver.data();
      final batch = FirebaseFirestore.instance.batch();
      batch.update(order.reference, {
        'driverId': driver.id,
        'deliveryStatus': 'assigned',
        'assignedAt': FieldValue.serverTimestamp(),
        'assignedBy': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(FirebaseFirestore.instance.collection('deliveryEvents').doc(), {
        'orderId': order.id,
        'driverId': driver.id,
        'status': 'assigned',
        'assignedBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(FirebaseFirestore.instance.collection('auditLogs').doc(), {
        'actorUid': user.uid,
        'email': user.email,
        'role': await _auth.role(),
        'action': 'smart_dispatch_assign',
        'result': 'success',
        'source': 'smart_dispatch',
        'details': {
          'orderId': order.id,
          'driverId': driver.id,
          'score': _score(driverData),
        },
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      _message('تم إسناد الطلب للمندوب الأفضل حالياً.');
    } on FirebaseException catch (e) {
      _message('تعذر الإسناد: ${e.message ?? e.code}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showAssignDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> order,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> drivers,
  ) async {
    final ranked = [...drivers]
      ..sort((a, b) => _score(b.data()).compareTo(_score(a.data())));
    if (ranked.isEmpty) {
      _message('لا يوجد مندوبون مؤهلون حالياً.');
      return;
    }

    final selected = await showModalBottomSheet<QueryDocumentSnapshot<Map<String, dynamic>>>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'اختيار المندوب',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              ...ranked.map((driver) {
                final data = driver.data();
                return Card(
                  elevation: 0,
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(
                        data['isOnline'] == true
                            ? Icons.wifi_tethering
                            : Icons.wifi_off_outlined,
                      ),
                    ),
                    title: Text(
                      '${data['name'] ?? data['displayName'] ?? driver.id}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      'الحمولة: ${data['activeOrderCount'] ?? 0} • '
                      'التقييم: ${data['rating'] ?? 5} • '
                      'النقاط: ${_score(data).toStringAsFixed(1)}',
                    ),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => Navigator.pop(context, driver),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );

    if (selected != null) await _assign(order, selected);
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: FutureBuilder<bool>(
        future: _staff(),
        builder: (context, access) {
          if (access.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (access.data != true) {
            return const Scaffold(
              body: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('مركز التوزيع الذكي مخصص للإدارة المصرح لها.'),
                ),
              ),
            );
          }

          final orders = FirebaseFirestore.instance
              .collection('orders')
              .where('deliveryStatus', isEqualTo: 'awaiting_assignment')
              .limit(50)
              .snapshots();
          final drivers = FirebaseFirestore.instance
              .collection('drivers')
              .where('approved', isEqualTo: true)
              .limit(100)
              .snapshots();

          return Scaffold(
            appBar: AppBar(title: const Text('التوزيع الذكي')),
            body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: orders,
              builder: (context, orderSnap) {
                if (orderSnap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('تعذر تحميل الطلبات: ${orderSnap.error}'),
                    ),
                  );
                }
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: drivers,
                  builder: (context, driverSnap) {
                    if (driverSnap.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('تعذر تحميل المندوبين: ${driverSnap.error}'),
                        ),
                      );
                    }

                    final ordersDocs = orderSnap.data?.docs ??
                        <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                    final driverDocs = driverSnap.data?.docs ??
                        <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                    final ranked = [...driverDocs]
                      ..sort((a, b) => _score(b.data()).compareTo(_score(a.data())));

                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Card(
                          elevation: 0,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.alt_route, size: 38),
                                const SizedBox(height: 8),
                                const Text(
                                  'محرك التوزيع الذكي',
                                  style: TextStyle(
                                    fontSize: 25,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'يرتب المندوبين حسب الاعتماد، الاتصال، الحمولة، التقييم وتوفر الموقع.',
                                ),
                                const SizedBox(height: 12),
                                Text('طلبات تنتظر الإسناد: ${ordersDocs.length}'),
                                Text('مندوبون معتمدون: ${driverDocs.length}'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (ordersDocs.isEmpty)
                          const Card(
                            elevation: 0,
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('لا توجد طلبات تنتظر التوزيع حالياً.'),
                            ),
                          ),
                        ...ordersDocs.map(
                          (order) => _DispatchCard(
                            order: order,
                            recommended: ranked.isEmpty ? null : ranked.first,
                            busy: _busy,
                            onAssign: _showAssignDialog,
                            drivers: driverDocs,
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _DispatchCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> order;
  final QueryDocumentSnapshot<Map<String, dynamic>>? recommended;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> drivers;
  final bool busy;
  final Future<void> Function(
    QueryDocumentSnapshot<Map<String, dynamic>>,
    List<QueryDocumentSnapshot<Map<String, dynamic>>>,
  ) onAssign;

  const _DispatchCard({
    required this.order,
    required this.recommended,
    required this.drivers,
    required this.busy,
    required this.onAssign,
  });

  @override
  Widget build(BuildContext context) {
    final data = order.data();
    final driver = recommended?.data();
    final shortId = order.id.substring(0, order.id.length > 8 ? 8 : order.id.length);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('طلب #$shortId', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            Text('العنوان: ${data['address'] ?? '—'}'),
            Text('الإجمالي: ${data['total'] ?? 0} ${data['currency'] ?? 'YER'}'),
            const SizedBox(height: 10),
            if (recommended != null)
              Text(
                'المقترح: ${driver?['name'] ?? driver?['displayName'] ?? recommended!.id} • الحمولة ${driver?['activeOrderCount'] ?? 0}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: busy || drivers.isEmpty ? null : () => onAssign(order, drivers),
              icon: const Icon(Icons.route_outlined),
              label: Text(recommended == null ? 'اختر مندوباً' : 'توزيع ذكي'),
            ),
          ],
        ),
      ),
    );
  }
}
