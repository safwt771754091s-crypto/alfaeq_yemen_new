import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_sections.dart';
import '../services/auth_service.dart';
import 'location_picker_page.dart';

class AdminDataEntry extends StatefulWidget {
  const AdminDataEntry({super.key});

  @override
  State<AdminDataEntry> createState() => _AdminDataEntryState();
}

class _AdminDataEntryState extends State<AdminDataEntry> {
  final _auth = AuthService();
  final _storeName = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _productName = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController();
  final _imageUrl = TextEditingController();

  String _sectionId = appSections.first.id;
  String? _selectedStoreId;
  String? _selectedStoreSectionId;
  LatLng? _storeLocation;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_storeName, _phone, _address, _productName, _description, _price, _stock, _imageUrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<bool> _allowed() async => _auth.hasAdminClaim();

  Future<void> _pickStoreLocation({LatLng? initial}) async {
    final result = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(
          initialLatitude: initial?.latitude,
          initialLongitude: initial?.longitude,
          title: 'تحديد موقع المتجر بدقة',
        ),
      ),
    );
    if (result != null && mounted) setState(() => _storeLocation = result);
  }

  Future<void> _createStore() async {
    final user = FirebaseAuth.instance.currentUser;
    final name = _storeName.text.trim();
    final phone = _phone.text.trim();
    if (user == null || name.isEmpty || phone.isEmpty) {
      _message('أدخل اسم المتجر ورقم الهاتف.');
      return;
    }
    if (_storeLocation == null) {
      _message('حدد موقع المتجر على الخريطة قبل الحفظ.');
      return;
    }

    setState(() => _saving = true);
    try {
      final point = GeoPoint(_storeLocation!.latitude, _storeLocation!.longitude);
      final ref = await FirebaseFirestore.instance.collection('stores').add({
        'name': name,
        'phone': phone,
        'address': _address.text.trim(),
        'sectionId': _sectionId,
        'status': 'approved',
        'ownerId': user.uid,
        'createdBy': user.uid,
        'ownerType': 'platform_admin',
        'location': point,
        'latitude': point.latitude,
        'longitude': point.longitude,
        'locationSource': 'admin_map_picker',
        'locationUpdatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      setState(() {
        _selectedStoreId = ref.id;
        _selectedStoreSectionId = _sectionId;
      });
      _storeName.clear();
      _phone.clear();
      _address.clear();
      _storeLocation = null;
      _message('تم حفظ المتجر مع إحداثياته الدقيقة في Firestore.');
    } on FirebaseException catch (e) {
      _message('تعذر حفظ المتجر: ${e.message ?? e.code}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createProduct() async {
    final user = FirebaseAuth.instance.currentUser;
    final storeId = _selectedStoreId;
    final name = _productName.text.trim();
    final price = num.tryParse(_price.text.trim());
    final stock = int.tryParse(_stock.text.trim());

    if (user == null || storeId == null || name.isEmpty) {
      _message('اختر المتجر وأدخل اسم الصنف.');
      return;
    }
    if (price == null || price < 0 || stock == null || stock < 0) {
      _message('السعر والكمية يجب أن يكونا أرقاماً صحيحة وغير سالبة.');
      return;
    }

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('products').add({
        'storeId': storeId,
        'sectionId': _selectedStoreSectionId ?? _sectionId,
        'ownerId': user.uid,
        'createdBy': user.uid,
        'name': name,
        'description': _description.text.trim(),
        'imageUrl': _imageUrl.text.trim(),
        'price': price,
        'currency': 'YER',
        'stock': stock,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _productName.clear();
      _description.clear();
      _price.clear();
      _stock.clear();
      _imageUrl.clear();
      _message('تم حفظ الصنف الحقيقي في Firestore وسيظهر في كتالوج المتجر.');
    } on FirebaseException catch (e) {
      _message('تعذر حفظ الصنف: ${e.message ?? e.code}');
    } finally {
      if (mounted) setState(() => _saving = false);
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
      child: FutureBuilder<bool>(
        future: _allowed(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.data != true) {
            return const Scaffold(body: Center(child: Text('هذه الصفحة مخصصة لحساب الأدمن.')));
          }
          return Scaffold(
            appBar: AppBar(title: const Text('البيانات الحقيقية — Firestore')),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.cloud_done_outlined),
                    title: Text('قاعدة البيانات الحقيقية', style: TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: Text('أي متجر أو صنف تحفظه هنا يُكتب مباشرة في Cloud Firestore، وليس بيانات تجريبية.'),
                  ),
                ),
                const SizedBox(height: 18),
                const Text('المتاجر الحقيقية', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                _stores(),
                const SizedBox(height: 18),
                const Text('إضافة متجر حقيقي', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _sectionId,
                          decoration: const InputDecoration(labelText: 'القسم'),
                          items: [for (final s in appSections) DropdownMenuItem(value: s.id, child: Text(s.title))],
                          onChanged: (v) => setState(() => _sectionId = v ?? _sectionId),
                        ),
                        TextField(controller: _storeName, decoration: const InputDecoration(labelText: 'اسم المتجر الحقيقي')),
                        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
                        TextField(controller: _address, decoration: const InputDecoration(labelText: 'العنوان')),
                        const SizedBox(height: 12),
                        Card(
                          elevation: 0,
                          child: ListTile(
                            leading: Icon(_storeLocation == null ? Icons.location_off_outlined : Icons.location_on),
                            title: Text(_storeLocation == null ? 'موقع المتجر غير محدد' : 'تم تحديد موقع المتجر'),
                            subtitle: Text(_storeLocation == null ? 'اضغط لتحديد الموقع على الخريطة' : '${_storeLocation!.latitude.toStringAsFixed(6)}, ${_storeLocation!.longitude.toStringAsFixed(6)}'),
                            trailing: const Icon(Icons.map_outlined),
                            onTap: _saving ? null : () => _pickStoreLocation(initial: _storeLocation),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _saving ? null : () => _pickStoreLocation(initial: _storeLocation), icon: const Icon(Icons.pin_drop_outlined), label: const Text('تحديد موقع المتجر على الخريطة'))),
                        const SizedBox(height: 8),
                        SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _saving ? null : _createStore, icon: const Icon(Icons.add_business), label: const Text('حفظ المتجر في قاعدة البيانات'))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text('إضافة صنف حقيقي', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        if (_selectedStoreId == null) const Align(alignment: Alignment.centerRight, child: Text('اختر متجراً من القائمة أولاً.')),
                        TextField(controller: _productName, decoration: const InputDecoration(labelText: 'اسم الصنف الحقيقي')),
                        TextField(controller: _description, maxLines: 2, decoration: const InputDecoration(labelText: 'وصف الصنف')),
                        TextField(controller: _price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر الحقيقي بالريال اليمني')),
                        TextField(controller: _stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المخزون')),
                        TextField(controller: _imageUrl, decoration: const InputDecoration(labelText: 'رابط صورة الصنف (اختياري)')),
                        const SizedBox(height: 12),
                        SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _saving || _selectedStoreId == null ? null : _createProduct, icon: const Icon(Icons.add_box), label: const Text('حفظ الصنف في قاعدة البيانات'))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text('الأصناف الموجودة فعلياً', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                _products(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _stores() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('stores').orderBy('createdAt', descending: true).limit(100).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text('تعذر تحميل المتاجر: ${snapshot.error}');
          if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
          final docs = snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          if (docs.isEmpty) return const Card(child: ListTile(title: Text('لا توجد متاجر بعد.')));
          return Column(children: docs.map((doc) {
            final data = doc.data();
            final selected = _selectedStoreId == doc.id;
            final lat = data['latitude'];
            final lng = data['longitude'];
            return Card(
              child: ListTile(
                selected: selected,
                leading: Icon(data['location'] is GeoPoint ? Icons.location_on : Icons.location_off_outlined),
                title: Text('${data['name'] ?? 'متجر'}', style: const TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text('${data['status'] ?? 'pending'} • ${data['phone'] ?? ''}\n${lat is num && lng is num ? 'الموقع: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}' : 'الموقع غير محدد'}'),
                isThreeLine: true,
                trailing: selected ? const Icon(Icons.check_circle) : const Icon(Icons.chevron_left),
                onTap: () => setState(() {
                  _selectedStoreId = doc.id;
                  _selectedStoreSectionId = data['sectionId'] as String?;
                }),
              ),
            );
          }).toList());
        },
      );

  Widget _products() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('products').orderBy('createdAt', descending: true).limit(150).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text('تعذر تحميل الأصناف: ${snapshot.error}');
          if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
          final docs = snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          final visible = _selectedStoreId == null ? docs : docs.where((d) => d.data()['storeId'] == _selectedStoreId).toList();
          if (visible.isEmpty) return const Card(child: ListTile(title: Text('لا توجد أصناف لهذا المتجر بعد.')));
          return Column(children: visible.map((doc) {
            final data = doc.data();
            return Card(child: ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text('${data['name'] ?? 'صنف'}', style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${data['description'] ?? ''}\nالمخزون: ${data['stock'] ?? 0} • الحالة: ${data['status'] ?? 'active'}'),
              isThreeLine: true,
              trailing: Text('${data['price'] ?? 0} ${data['currency'] ?? 'YER'}', style: const TextStyle(fontWeight: FontWeight.w900)),
            ));
          }).toList());
        },
      );
}
