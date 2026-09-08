import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/dispatch_service.dart';

class DispatchCenterPage extends StatefulWidget {
  const DispatchCenterPage({super.key});

  @override
  State<DispatchCenterPage> createState() => _DispatchCenterPageState();
}

class _DispatchCenterPageState extends State<DispatchCenterPage> {
  final _auth = AuthService();
  final _dispatch = DispatchService();
  bool _busy = false;

  Future<bool> _allowed() async {
    final role = await _auth.role();
    return role == 'admin' || role == 'owner' || role == 'developer';
  }

  Future<void> _setLocation(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final lat = TextEditingController();
    final lng = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تحديد موقع التسليم'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: lat,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(labelText: 'خط العرض'),
              ),
              TextField(
                controller: lng,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(labelText: 'خط الطول'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;
    final latitude = double.tryParse(lat.text.trim());
    final longitude = double.tryParse(lng.text.trim());
    if (latitude == null ||
        longitude == null ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      _message('الإحداثيات غير صحيحة.');
      return;
    }

    await doc.reference.update({
      'deliveryLocation': GeoPoint(latitude, longitude),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _message('تم حفظ موقع التسليم.');
  }

  Future<void> _assign(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final destination = doc.data()['deliveryLocation'];
    if (destination is! GeoPoint) {
      _message('حدد موقع التسليم أولاً.');
      return;
    }

    setState(() => _busy = true);
    try {
      final candidate = await _dispatch.assignBestDriver(
        orderId: doc.id,
        destination: destination,
        actorUid: user.uid,
        actorRole: await _auth.role(),
      );
      _message(
        candidate == null
            ? 'لا يوجد مندوب متاح بموقع صالح.'
            : 'تم التوزيع على ${candidate.driverId} ضمن ${candidate.distanceKm.toStringAsFixed(2)} كم.',
      );
    } on FirebaseException catch (e) {
      _message('تعذر التوزيع: ${e.message ?? e.code}');
    } on StateError catch (e) {
      _message(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text)),
      );
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
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (access.data != true) {
            return const Scaffold(
              body: Center(
                child: Text('مركز التوزيع الذكي مخصص للإدارة والمطورين.'),
              ),
            );
          }

          final stream = FirebaseFirestore.instance
              .collection('orders')
              .where('deliveryStatus', isEqualTo: 'awaiting_assignment')
              .limit(100)
              .snapshots();

          return Scaffold(
            appBar: AppBar(title: const Text('التوزيع الذكي')),
            body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'تعذر تحميل طابور التوزيع.\n${snapshot.error}',
                      ),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ??
                    const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                if (docs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('لا توجد طلبات بانتظار التوزيع حالياً.'),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();
                    final hasLocation = data['deliveryLocation'] is GeoPoint;
                    final shortId = doc.id.substring(
                      0,
                      doc.id.length > 8 ? 8 : doc.id.length,
                    );

                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(
                            hasLocation
                                ? Icons.route_outlined
                                : Icons.location_off_outlined,
                          ),
                        ),
                        title: Text(
                          'طلب #$shortId',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          '${data['address'] ?? '—'}\n${hasLocation ? 'موقع التسليم جاهز' : 'يحتاج موقع تسليم'}',
                        ),
                        isThreeLine: true,
                        trailing: Wrap(
                          spacing: 6,
                          children: [
                            IconButton(
                              tooltip: 'تحديد الموقع',
                              onPressed: _busy ? null : () => _setLocation(doc),
                              icon: const Icon(Icons.edit_location_alt_outlined),
                            ),
                            FilledButton.icon(
                              onPressed: _busy || !hasLocation
                                  ? null
                                  : () => _assign(doc),
                              icon: const Icon(Icons.auto_awesome),
                              label: const Text('توزيع'),
                            ),
                          ],
                        ),
                      ),
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
