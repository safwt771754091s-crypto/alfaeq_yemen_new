import 'package:flutter/material.dart';

import '../core/app_sections.dart';
import '../services/application_service.dart';
import '../services/profile_service.dart';

/// Self-service screen: a customer applies to open a store. The application is
/// reviewed by platform staff in the "طلبات التجار" page.
class MerchantApplicationPage extends StatefulWidget {
  const MerchantApplicationPage({super.key});

  @override
  State<MerchantApplicationPage> createState() => _MerchantApplicationPageState();
}

class _MerchantApplicationPageState extends State<MerchantApplicationPage> {
  final _svc = ApplicationService();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _storeName = TextEditingController();
  final _city = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  String _sectionId = appSections.first.id;

  bool _loading = true;
  bool _busy = false;
  Map<String, dynamic>? _application;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose(); _phone.dispose(); _storeName.dispose(); _city.dispose(); _address.dispose(); _notes.dispose();
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
      _application = await _svc.myMerchantApplication();
    } catch (_) {
      _application = null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_storeName.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      _message('أدخل اسم المتجر ورقم الهاتف على الأقل.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _svc.submitMerchantApplication(
        applicantName: _name.text.trim(),
        phone: _phone.text.trim(),
        storeName: _storeName.text.trim(),
        sectionId: _sectionId,
        city: _city.text.trim(),
        address: _address.text.trim(),
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
      await _svc.cancelMerchantApplication(id);
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
    if (text.contains('already_privileged')) return 'حسابك يملك صلاحية تاجر بالفعل.';
    if (text.contains('application_pending')) return 'لديك طلب قيد المراجعة بالفعل.';
    if (text.contains('phone_required')) return 'رقم الهاتف مطلوب.';
    if (text.contains('store_name_required')) return 'اسم المتجر مطلوب.';
    return 'تعذر إرسال الطلب: $e';
  }

  void _message(String t) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t))); }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('انضم كتاجر')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF0B6E4F), Color(0xFF124E78)]),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.storefront_outlined, color: Colors.white, size: 36),
                      SizedBox(height: 10),
                      Text('افتح متجرك على الفائق يمن', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                      SizedBox(height: 6),
                      Text('أرسل طلبك، وبعد الاعتماد ستُفتح لك بوابة التاجر لإدارة منتجاتك وطلباتك.', style: TextStyle(color: Colors.white70, height: 1.5)),
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
                          TextField(controller: _storeName, decoration: const InputDecoration(labelText: 'اسم المتجر *', border: OutlineInputBorder())),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _sectionId,
                            decoration: const InputDecoration(labelText: 'القسم', border: OutlineInputBorder()),
                            items: [for (final s in appSections) DropdownMenuItem(value: s.id, child: Text(s.title))],
                            onChanged: (v) { if (v != null) setState(() => _sectionId = v); },
                          ),
                          const SizedBox(height: 12),
                          TextField(controller: _city, decoration: const InputDecoration(labelText: 'المدينة', border: OutlineInputBorder())),
                          const SizedBox(height: 12),
                          TextField(controller: _address, decoration: const InputDecoration(labelText: 'العنوان', border: OutlineInputBorder())),
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
          Text('المتجر: ${app['store_name'] ?? '—'}'),
          if (app['review_notes'] != null && '${app['review_notes']}'.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text('ملاحظة الإدارة: ${app['review_notes']}', style: const TextStyle(color: Colors.black54))),
          if (status == 'pending') ...[
            const SizedBox(height: 10),
            const Text('يمكنك إلغاء الطلب قبل مراجعته.', style: TextStyle(color: Colors.black54, fontSize: 12)),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _busy ? null : _cancel, icon: const Icon(Icons.close), label: const Text('إلغاء الطلب')),
          ],
          if (status == 'approved') ...[
            const SizedBox(height: 10),
            const Text('تم اعتمادك. أعد تشغيل التطبيق أو سجّل الدخول من جديد لتفتح بوابة التاجر.', style: TextStyle(color: Colors.black54)),
          ],
        ]),
      ),
    );
  }
}
