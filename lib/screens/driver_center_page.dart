import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class DriverCenterPage extends StatefulWidget {
  const DriverCenterPage({super.key});
  @override
  State<DriverCenterPage> createState() => _DriverCenterPageState();
}

class _DriverCenterPageState extends State<DriverCenterPage> {
  final _auth = AuthService();
  final _db = FirebaseFirestore.instance;
  bool _busy = false;

  Future<bool> _allowed() async {
    final role = await _auth.role();
    return role == 'driver' || role == 'admin' || role == 'owner' || role == 'developer';
  }

  Future<void> _toggleOnline(bool value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _busy = true);
    try {
      await _db.collection('drivers').doc(user.uid).set({
        'uid': user.uid,
        'isOnline': value,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      _message('تعذر تحديث حالة الاتصال: ${e.message ?? e.code}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateLocation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final lat = TextEditingController();
    final lng = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تحديث موقع المندوب'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: lat, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'خط العرض')),
            TextField(controller: lng, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'خط الطول')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final latitude = double.tryParse(lat.text.trim());
    final longitude = double.tryParse(lng.text.trim());
    if (latitude == null || longitude == null || latitude.abs() > 90 || longitude.abs() > 180) {
      _message('أدخل إحداثيات صحيحة.');
      return;
    }
    await _db.collection('drivers').doc(user.uid).set({
      'uid': user.uid,
      'currentLocation': GeoPoint(latitude, longitude),
      'lastSeenAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _message('تم تحديث الموقع.');
  }

  void _message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: FutureBuilder<bool>(
        future: _allowed(),
        builder: (context, access) {
          if (access.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          if (access.data != true || user == null) return const Scaffold(body: Center(child: Text('مركز المندوب محمي للحسابات المعتمدة.')));
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _db.collection('drivers').doc(user.uid).snapshots(),
            builder: (context, profile) {
              final data = profile.data?.data() ?? {};
              final approved = data['approved'] == true;
              final online = data['isOnline'] == true;
              final active = (data['activeOrderCount'] as num?)?.toInt() ?? 0;
              final rating = (data['rating'] as num?)?.toDouble() ?? 5.0;
              return Scaffold(
                appBar: AppBar(title: const Text('مركز المندوب')),
                body: ListView(padding: const EdgeInsets.all(16), children: [
                  Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.delivery_dining, size: 42),
                    const SizedBox(height: 10),
                    const Text('المندوب الذكي', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text(approved ? 'حسابك معتمد للتوزيع.' : 'بانتظار اعتماد حساب المندوب.'),
                    SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('متاح لاستلام الطلبات'), subtitle: Text(online ? 'متصل' : 'غير متصل'), value: online, onChanged: _busy || !approved ? null : _toggleOnline),
                  ]))),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _Stat(title: 'الطلبات النشطة', value: '$active', icon: Icons.assignment_outlined)),
                    const SizedBox(width: 10),
                    Expanded(child: _Stat(title: 'التقييم', value: rating.toStringAsFixed(1), icon: Icons.star_outline)),
                  ]),
                  const SizedBox(height: 12),
                  Card(elevation: 0, child: ListTile(leading: const Icon(Icons.my_location_outlined), title: const Text('موقع المندوب'), subtitle: Text(data['currentLocation'] is GeoPoint ? 'تم تسجيل الموقع وجاهز للتوزيع الذكي.' : 'لم يتم تسجيل موقع بعد.'), trailing: const Icon(Icons.edit_location_alt_outlined), onTap: approved ? _updateLocation : null)),
                  const SizedBox(height: 12),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _db.collection('orders').where('driverId', isEqualTo: user.uid).limit(50).snapshots(),
                    builder: (context, orders) {
                      if (orders.hasError) return Text('تعذر تحميل الطلبات: ${orders.error}');
                      final docs = orders.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                      return Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('مهام التوصيل', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        if (docs.isEmpty) const Text('لا توجد مهام مسندة حالياً.') else ...docs.map((doc) => _DriverOrderTile(doc: doc)),
                      ])));
                    },
                  ),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String title, value;
  final IconData icon;
  const _Stat({required this.title, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) => Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [Icon(icon), const SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), Text(title)])])));
}

class _DriverOrderTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _DriverOrderTile({required this.doc});
  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    return ListTile(contentPadding: EdgeInsets.zero, leading: const CircleAvatar(child: Icon(Icons.local_shipping_outlined)), title: Text('طلب #${doc.id.substring(0, doc.id.length > 8 ? 8 : doc.id.length)}'), subtitle: Text('${data['deliveryStatus'] ?? 'assigned'} • ${data['address'] ?? '—'}'));
  }
}
