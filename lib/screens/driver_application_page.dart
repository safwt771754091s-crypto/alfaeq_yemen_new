import 'package:flutter/material.dart';

import '../services/application_service.dart';
import '../services/profile_service.dart';

/// Self-service screen: a customer applies to become a delivery driver. The
/// application is reviewed by platform staff in the "طلبات المندوبين" page,
/// then the driver is activated in the dispatch centre.
class DriverApplicationPage extends StatefulWidget {
  const DriverApplicationPage({super.key});

  @override
  State<DriverApplicationPage> createState() => _DriverApplicationPageState();
}

class _DriverApplicationPageState extends State<DriverApplicationPage> {
  final _svc = ApplicationService();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _plate = TextEditingController();
  final _city = TextEditingController();
  final _notes = TextEditingController();
  String _vehicle = 'دراجة نارية';

  bool _loading = true;
  bool _busy = false;
  Map<String, dynamic>? _application;

  static const _vehicles = ['دراجة نارية', 'سيارة', 'شاحنة صغيرة', 'دراجة هوائية', 'أخرى'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose(); _phone.dispose(); _plate.dispose(); _city.dispose(); _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final profile = await ProfileService().load();
      _name.text = (profile['display_name'] ?? profile['name'] ?? '').toString();
      _phone.text = (profile['phone'] ?? '').toString();
    } catch (_) {}
    try {
      _application = await _svc.myDriverApplication();
    } catch (_) {
      _application = null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_phone.text.trim().isEmpty) {
      _message('أدخل رقم الهاتف على الأقل.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _svc.submitDriverApplication(
        applicantName: _name.text.trim(),
        phone: _phone.text.trim(),
        vehicleType: _vehicle,
        vehiclePlate: _plate.text.trim(),
        city: _city.text.trim(),
        notes: _notes.text.trim(),
      );
      _message('تم إرسال طلبك بنجاح. ستتم مراجعته من إدارة المنصة.');
      await _load();
    } catch (e) {
      _message(_friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final id = _application?['id']?.toString();
    if (id == null) return;
    setState(() => _busy = true);
    try {
      await _svc.cancelDriverApplication(id);
      _message('تم إلغاء الطلب.');
      await _load();
    } catch (e) {
      _message(_friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(Object e) {
    final text = e.toString();
    if (text.contains('already_privileged')) return 'حسابك يملك صلاحية عمل بالفعل.';
    if (text.contains('application_pending')) return 'لديك طلب قيد المراجعة بالفعل.';
    if (text.contains('phone_required')) return 'رقم الهاتف مطلوب.';
    return 'تعذر إرسال الطلب: $e';
  }

  void _message(String t) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t))); }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('انضم كمندوب توصيل')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF124E78), Color(0xFF0B6E4F)]),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.delivery_dining, color: Colors.white, size: 36),
                      SizedBox(height: 10),
                      Text('اعمل مندوب توصيل', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                      SizedBox(height: 6),
                      Text('أرسل طلبك، وبعد الاعتماد ستتمكن من استلام مهام التوصيل وتتبّع أرباحك.', style: TextStyle(color: Colors.white70, height: 1.5)),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  if (_application != null) _statusCard(_application!),
                  if (_application == null || _application!['status'] == 'rejected' || _application!['status'] == 'cancelled') ...[
                    Card(
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          TextField(controller: _name, decoration: const InputDecoration(labelText: 'اسمك الكامل', border: OutlineInputBorder())),
                          const SizedBox(height: 12),
                          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف *', border: OutlineInputBorder())),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _vehicle,
                            decoration: const InputDecoration(labelText: 'نوع المركبة', border: OutlineInputBorder()),
                            items: [for (final v in _vehicles) DropdownMenuItem(value: v, child: Text(v))],
                            onChanged: (v) { if (v != null) setState(() => _vehicle = v); },
                          ),
                          const SizedBox(height: 12),
                          TextField(controller: _plate, decoration: const InputDecoration(labelText: 'رقم اللوحة (اختياري)', border: OutlineInputBorder())),
                          const SizedBox(height: 12),
                          TextField(controller: _city, decoration: const InputDecoration(labelText: 'المدينة', border: OutlineInputBorder())),
                          const SizedBox(height: 12),
                          TextField(controller: _notes, maxLines: 3, decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)', border: OutlineInputBorder())),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _busy ? null : _submit,
                              icon: const Icon(Icons.send_outlined),
                              label: Text(_busy ? 'جاري الإرسال...' : 'إرسال طلب الانضمام'),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _statusCard(Map<String, dynamic> app) {
    final status = '${app['status'] ?? 'pending'}';
    final (label, color, icon) = switch (status) {
      'approved' => ('معتمد', Colors.green, Icons.verified),
      'rejected' => ('مرفوض', Colors.red, Icons.cancel_outlined),
      'cancelled' => ('ملغى', Colors.grey, Icons.remove_circle_outline),
      _ => ('قيد المراجعة', Colors.orange, Icons.hourglass_top),
    };
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Text('حالة طلبك: $label', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: color)),
          ]),
          const SizedBox(height: 8),
          Text('المركبة: ${app['vehicle_type'] ?? '—'}'),
          if (app['review_notes'] != null && '${app['review_notes']}'.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text('ملاحظة الإدارة: ${app['review_notes']}', style: const TextStyle(color: Colors.black54))),
          if (status == 'pending') ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: _busy ? null : _cancel, icon: const Icon(Icons.close), label: const Text('إلغاء الطلب')),
          ],
          if (status == 'approved') ...[
            const SizedBox(height: 10),
            const Text('تم اعتمادك. سيتم تفعيل حسابك في لوحة التوزيع، ثم أعد تشغيل التطبيق.', style: TextStyle(color: Colors.black54)),
          ],
        ]),
      ),
    );
  }
}
