import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class DriverCenterPage extends StatefulWidget {
  const DriverCenterPage({super.key});
  @override State<DriverCenterPage> createState() => _DriverCenterPageState();
}

class _DriverCenterPageState extends State<DriverCenterPage> {
  final _auth = AuthService();
  final _db = FirebaseFirestore.instance;
  bool _busy = false;

  Future<bool> _allowed() async {
    final role = await _auth.role();
    return role == 'driver' || role == 'admin' || role == 'owner' || role == 'developer';
  }

  Future<void> _ensureProfile(String uid) async {
    final ref = _db.collection('drivers').doc(uid);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({'uid': uid, 'approved': false, 'isOnline': false, 'activeOrderCount': 0, 'rating': 5.0, 'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()});
    }
  }

  Future<void> _toggleOnline(bool value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _busy = true);
    try {
      await _ensureProfile(user.uid);
      await _db.collection('drivers').doc(user.uid).update({'isOnline': value, 'lastSeenAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()});
    } on FirebaseException catch (e) { _message('تعذر تحديث حالة الاتصال: ${e.message ?? e.code}'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _updateLocation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final lat = TextEditingController();
    final lng = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (context) => Directionality(textDirection: TextDirection.rtl, child: AlertDialog(
      title: const Text('تحديث موقع المندوب'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: lat, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'خط العرض')),
        TextField(controller: lng, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'خط الطول')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ'))],
    )));
    if (ok != true) return;
    final latitude = double.tryParse(lat.text.trim());
    final longitude = double.tryParse(lng.text.trim());
    if (latitude == null || longitude == null || latitude.abs() > 90 || longitude.abs() > 180) { _message('أدخل إحداثيات صحيحة.'); return; }
    await _ensureProfile(user.uid);
    await _db.collection('drivers').doc(user.uid).update({'currentLocation': GeoPoint(latitude, longitude), 'lastSeenAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()});
    _message('تم تحديث الموقع.');
  }

  Future<void> _setDeliveryStatus(QueryDocumentSnapshot<Map<String, dynamic>> doc, String status) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _busy = true);
    try {
      final orderRef = doc.reference;
      final driverRef = _db.collection('drivers').doc(user.uid);
      await _db.runTransaction((tx) async {
        final order = await tx.get(orderRef);
        final driver = await tx.get(driverRef);
        if (!order.exists || !driver.exists) throw StateError('بيانات المهمة غير متاحة.');
        final data = order.data() ?? {};
        if (data['driverId'] != user.uid) throw StateError('هذه المهمة ليست مسندة إليك.');
        final update = <String, dynamic>{'deliveryStatus': status, 'updatedAt': FieldValue.serverTimestamp()};
        if (status == 'delivered') update['deliveredAt'] = FieldValue.serverTimestamp();
        tx.update(orderRef, update);
        if (status == 'delivered') {
          final active = (driver.data()?['activeOrderCount'] as num?)?.toInt() ?? 0;
          tx.update(driverRef, {'activeOrderCount': active > 0 ? active - 1 : 0, 'updatedAt': FieldValue.serverTimestamp()});
        }
      });
      _message('تم تحديث مهمة التوصيل.');
    } on FirebaseException catch (e) { _message('تعذر تحديث المهمة: ${e.message ?? e.code}'); }
    on StateError catch (e) { _message(e.message); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  void _message(String text) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Directionality(textDirection: TextDirection.rtl, child: FutureBuilder<bool>(future: _allowed(), builder: (context, access) {
      if (access.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      if (access.data != true || user == null) return const Scaffold(body: Center(child: Text('مركز المندوب محمي للحسابات المعتمدة.')));
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(stream: _db.collection('drivers').doc(user.uid).snapshots(), builder: (context, profile) {
        final data = profile.data?.data() ?? {};
        final approved = data['approved'] == true;
        final online = data['isOnline'] == true;
        final active = (data['activeOrderCount'] as num?)?.toInt() ?? 0;
        final rating = (data['rating'] as num?)?.toDouble() ?? 5.0;
        return Scaffold(appBar: AppBar(title: const Text('مركز المندوب')), body: ListView(padding: const EdgeInsets.all(16), children: [
          Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.delivery_dining, size: 42), const SizedBox(height: 10),
            const Text('المندوب الذكي', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)), const SizedBox(height: 6),
            Text(approved ? 'حسابك معتمد للتوزيع.' : 'بانتظار اعتماد حساب المندوب.'),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('متاح لاستلام الطلبات'), subtitle: Text(online ? 'متصل' : 'غير متصل'), value: online, onChanged: _busy || !approved ? null : _toggleOnline),
          ]))),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: _Stat(title: 'الطلبات النشطة', value: '$active', icon: Icons.assignment_outlined)), const SizedBox(width: 10), Expanded(child: _Stat(title: 'التقييم', value: rating.toStringAsFixed(1), icon: Icons.star_outline))]),
          const SizedBox(height: 12),
          Card(elevation: 0, child: ListTile(leading: const Icon(Icons.my_location_outlined), title: const Text('موقع المندوب'), subtitle: Text(data['currentLocation'] is GeoPoint ? 'تم تسجيل الموقع وجاهز للتوزيع الذكي.' : 'لم يتم تسجيل موقع بعد.'), trailing: const Icon(Icons.edit_location_alt_outlined), onTap: approved ? _updateLocation : null)),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: _db.collection('orders').where('driverId', isEqualTo: user.uid).limit(50).snapshots(), builder: (context, orders) {
            if (orders.hasError) return Text('تعذر تحميل الطلبات: ${orders.error}');
            final docs = orders.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            return Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('مهام التوصيل', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)), const SizedBox(height: 10),
              if (docs.isEmpty) const Text('لا توجد مهام مسندة حالياً.') else ...docs.map((doc) => _DriverOrderTile(doc: doc, busy: _busy, onStatus: _setDeliveryStatus)),
            ])));
          }),
        ]));
      });
    }));
  }
}

class _Stat extends StatelessWidget {
  final String title, value; final IconData icon;
  const _Stat({required this.title, required this.value, required this.icon});
  @override Widget build(BuildContext context) => Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [Icon(icon), const SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), Text(title)])])));
}

class _DriverOrderTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc; final bool busy; final Future<void> Function(QueryDocumentSnapshot<Map<String, dynamic>>, String) onStatus;
  const _DriverOrderTile({required this.doc, required this.busy, required this.onStatus});
  @override Widget build(BuildContext context) {
    final data = doc.data(); final status = '${data['deliveryStatus'] ?? 'assigned'}';
    return Card(elevation: 0, child: ExpansionTile(leading: const Icon(Icons.local_shipping_outlined), title: Text('طلب #${doc.id.substring(0, doc.id.length > 8 ? 8 : doc.id.length)}'), subtitle: Text('${status} • ${data['address'] ?? '—'}'), children: [
      Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 8, runSpacing: 8, children: [
        if (status == 'assigned') FilledButton(onPressed: busy ? null : () => onStatus(doc, 'picked_up'), child: const Text('استلام الطلب')),
        if (status == 'picked_up') FilledButton(onPressed: busy ? null : () => onStatus(doc, 'out_for_delivery'), child: const Text('خرج للتوصيل')),
        if (status == 'out_for_delivery') FilledButton(onPressed: busy ? null : () => onStatus(doc, 'delivered'), child: const Text('تم التسليم')),
      ])),
    ]));
  }
}
