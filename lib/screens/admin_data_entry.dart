import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_sections.dart';
import '../core/product_units.dart';
import '../services/auth_service.dart';
import '../services/media_service.dart';
import '../services/supabase_service.dart';
import 'bulk_product_import_page.dart';
import 'location_picker_page.dart';
import 'store_map_page.dart';

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
  String _saleUnit = 'piece';
  String _sectionId = appSections.first.id;
  String? _selectedStoreId;
  String? _selectedStoreSectionId;
  LatLng? _storeLocation;
  bool _saving = false;
  String? _uploadedImageUrl;

  @override
  void dispose() {
    for (final c in [_storeName, _phone, _address, _productName, _description, _price, _stock, _imageUrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<bool> _allowed() => _auth.hasAdminClaim();

  Future<void> _openBulkImport() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const BulkProductImportPage()));
  }

  Future<void> _pickProductImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.single.bytes == null || !mounted) return;
    final file = result.files.single;
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      _message('يجب تسجيل الدخول أولاً.');
      return;
    }
    setState(() => _saving = true);
    try {
      final ext = file.extension ?? 'jpg';
      final url = await MediaService.uploadProductImage(
        ownerId: user.id,
        bytes: file.bytes!,
        extension: ext,
      );
      if (!mounted) return;
      setState(() {
        _uploadedImageUrl = url;
        _imageUrl.text = url;
      });
      _message('تم رفع صورة الصنف إلى قاعدة صور الفائق في Supabase.');
    } catch (e) {
      _message('تعذر رفع الصورة: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openStoreMap() async {
    try {
      final rows = await SupabaseService.client
          .from('stores')
          .select('id,name,latitude,longitude,status')
          .order('created_at', ascending: false)
          .limit(500);
      if (!mounted) return;
      final stores = (rows as List).whereType<Map<String, dynamic>>().toList();
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => StoreMapPage(stores: stores)),
      );
    } catch (e) {
      _message('تعذر تحميل خريطة المتاجر: $e');
    }
  }

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

  String _newId(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _createStore() async {
    final user = SupabaseService.client.auth.currentUser;
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
      final now = DateTime.now().toUtc().toIso8601String();
      final id = _newId(user.id);
      await SupabaseService.client.from('stores').insert({
        'id': id,
        'owner_id': user.id,
        'name': name,
        'phone': phone,
        'address': _address.text.trim(),
        'section_id': _sectionId,
        'status': 'approved',
        'latitude': _storeLocation!.latitude,
        'longitude': _storeLocation!.longitude,
        'location': {
          'latitude': _storeLocation!.latitude,
          'longitude': _storeLocation!.longitude,
          'source': 'admin_map_picker',
        },
        'metadata': {'owner_type': 'platform_admin', 'created_by': user.id},
        'created_at': now,
        'updated_at': now,
      });
      if (!mounted) return;
      setState(() {
        _selectedStoreId = id;
        _selectedStoreSectionId = _sectionId;
      });
      _storeName.clear();
      _phone.clear();
      _address.clear();
      _storeLocation = null;
      _message('تم حفظ المتجر الحقيقي في Supabase.');
    } catch (e) {
      _message('تعذر حفظ المتجر: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createProduct() async {
    final user = SupabaseService.client.auth.currentUser;
    final storeId = _selectedStoreId;
    final name = _productName.text.trim();
    final price = num.tryParse(_price.text.trim());
    final stock = num.tryParse(_stock.text.trim());
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
      final unit = ProductUnit.fromId(_saleUnit);
      final productId = _newId(user.id);
      final imageUrl = _imageUrl.text.trim();
      await SupabaseService.client.from('products').insert({
        'id': productId,
        'store_id': storeId,
        'section_id': _selectedStoreSectionId ?? _sectionId,
        'owner_id': user.id,
        'name': name,
        'description': _description.text.trim(),
        'image_url': imageUrl,
        'price': price,
        'currency': 'YER',
        'stock': stock,
        'stock_base': unit.toBase(stock).round(),
        'sale_unit': _saleUnit,
        'unit_label': unit.label,
        'base_unit': unit.baseUnit,
        'unit_scale': unit.scale,
        'step_base': unit.defaultStepBase,
        'min_order_base': unit.defaultStepBase,
        'sold_quantity': 0,
        'sold_quantity_base': 0,
        'status': 'active',
        'metadata': {'created_by': user.id, 'source': 'admin_data_entry'},
      });
      if (imageUrl.isNotEmpty) {
        await SupabaseService.client
            .from('media_assets')
            .update({'entity_id': productId})
            .eq('owner_id', user.id)
            .eq('public_url', imageUrl)
            .isFilter('entity_id', null);
      }
      _productName.clear();
      _description.clear();
      _price.clear();
      _stock.clear();
      _imageUrl.clear();
      _uploadedImageUrl = null;
      _message('تم حفظ الصنف الحقيقي في Supabase.');
    } catch (e) {
      _message('تعذر حفظ الصنف: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
            appBar: AppBar(
              title: const Text('البيانات الحقيقية — Supabase'),
              actions: [
                IconButton(
                  tooltip: 'خريطة المتاجر',
                  onPressed: _saving ? null : _openStoreMap,
                  icon: const Icon(Icons.map_outlined),
                ),
                IconButton(
                  tooltip: 'استيراد أصناف بالجملة',
                  onPressed: _saving ? null : _openBulkImport,
                  icon: const Icon(Icons.upload_file_outlined),
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.cloud_done_outlined),
                    title: Text('قاعدة البيانات الحقيقية', style: TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: Text('المتاجر والأصناف تُحفظ مباشرة في Supabase الإنتاجي.'),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.upload_file_outlined)),
                    title: const Text('استيراد الأصناف بالجملة', style: TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: const Text('Excel أو CSV مع فحص المراجع قبل الإدخال.'),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: _openBulkImport,
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
                          items: [
                            for (final s in appSections) DropdownMenuItem(value: s.id, child: Text(s.title)),
                          ],
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
                            subtitle: Text(_storeLocation == null
                                ? 'اضغط لتحديد الموقع على الخريطة'
                                : '${_storeLocation!.latitude.toStringAsFixed(6)}, ${_storeLocation!.longitude.toStringAsFixed(6)}'),
                            trailing: const Icon(Icons.map_outlined),
                            onTap: _saving ? null : () => _pickStoreLocation(initial: _storeLocation),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _saving ? null : () => _pickStoreLocation(initial: _storeLocation),
                            icon: const Icon(Icons.pin_drop_outlined),
                            label: const Text('تحديد موقع المتجر على الخريطة'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _createStore,
                            icon: const Icon(Icons.add_business),
                            label: const Text('حفظ المتجر في Supabase'),
                          ),
                        ),
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
                        if (_selectedStoreId == null)
                          const Align(alignment: Alignment.centerRight, child: Text('اختر متجراً من القائمة أولاً.')),
                        TextField(controller: _productName, decoration: const InputDecoration(labelText: 'اسم الصنف الحقيقي')),
                        TextField(controller: _description, maxLines: 2, decoration: const InputDecoration(labelText: 'وصف الصنف')),
                        TextField(controller: _price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر الحقيقي بالريال اليمني')),
                        TextField(
                          controller: _stock,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(labelText: 'المخزون بـ ${ProductUnit.fromId(_saleUnit).label}'),
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: _saleUnit,
                          decoration: const InputDecoration(labelText: 'وحدة البيع'),
                          items: [
                            for (final u in ProductUnit.all) DropdownMenuItem(value: u.id, child: Text(u.label)),
                          ],
                          onChanged: (v) => setState(() => _saleUnit = v ?? _saleUnit),
                        ),
                        TextField(controller: _imageUrl, decoration: const InputDecoration(labelText: 'رابط صورة الصنف (اختياري)')),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _saving ? null : _pickProductImage,
                            icon: const Icon(Icons.photo_library_outlined),
                            label: Text(_uploadedImageUrl == null ? 'رفع صورة من الجهاز إلى قاعدة الصور' : 'تم رفع صورة المنتج'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _saving || _selectedStoreId == null ? null : _createProduct,
                            icon: const Icon(Icons.add_box),
                            label: const Text('حفظ الصنف في Supabase'),
                          ),
                        ),
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

  Widget _stores() => StreamBuilder<List<Map<String, dynamic>>>(
        stream: SupabaseService.client.from('stores').stream(primaryKey: ['id']).order('created_at', ascending: false).limit(100),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text('تعذر تحميل المتاجر: ${snapshot.error}');
          if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
          final rows = snapshot.data ?? const <Map<String, dynamic>>[];
          if (rows.isEmpty) return const Card(child: ListTile(title: Text('لا توجد متاجر بعد.')));
          return Column(
            children: rows.map((data) {
              final id = data['id']?.toString() ?? '';
              final selected = _selectedStoreId == id;
              final lat = data['latitude'];
              final lng = data['longitude'];
              return Card(
                child: ListTile(
                  selected: selected,
                  leading: Icon(lat is num && lng is num ? Icons.location_on : Icons.location_off_outlined),
                  title: Text('${data['name'] ?? 'متجر'}', style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text('${data['status'] ?? 'pending'} • ${data['phone'] ?? ''}\n${lat is num && lng is num ? 'الموقع: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}' : 'الموقع غير محدد'}'),
                  isThreeLine: true,
                  trailing: selected ? const Icon(Icons.check_circle) : const Icon(Icons.chevron_left),
                  onTap: () => setState(() {
                    _selectedStoreId = id;
                    _selectedStoreSectionId = data['section_id']?.toString();
                  }),
                ),
              );
            }).toList(),
          );
        },
      );

  Widget _products() => StreamBuilder<List<Map<String, dynamic>>>(
        stream: SupabaseService.client.from('products').stream(primaryKey: ['id']).order('created_at', ascending: false).limit(150),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text('تعذر تحميل الأصناف: ${snapshot.error}');
          if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
          final rows = snapshot.data ?? const <Map<String, dynamic>>[];
          final visible = _selectedStoreId == null
              ? rows
              : rows.where((p) => p['store_id']?.toString() == _selectedStoreId).toList();
          if (visible.isEmpty) return const Card(child: ListTile(title: Text('لا توجد أصناف لهذا المتجر بعد.')));
          return Column(
            children: visible.map((data) {
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text('${data['name'] ?? 'صنف'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${data['description'] ?? ''}\nالمخزون: ${data['stock'] ?? 0} • الحالة: ${data['status'] ?? 'active'}'),
                  isThreeLine: true,
                  trailing: Text('${data['price'] ?? 0} ${data['currency'] ?? 'YER'}', style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              );
            }).toList(),
          );
        },
      );
}
