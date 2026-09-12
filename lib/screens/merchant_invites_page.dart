import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MerchantInvitesPage extends StatefulWidget {
  const MerchantInvitesPage({super.key});

  @override
  State<MerchantInvitesPage> createState() => _MerchantInvitesPageState();
}

class _MerchantInvitesPageState extends State<MerchantInvitesPage> {
  final _label = TextEditingController();
  bool _busy = false;
  String? _lastLink;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _createInvite() async {
    final label = _label.text.trim();
    setState(() => _busy = true);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('createMerchantInvite');
      final result = await callable.call(<String, dynamic>{'label': label});
      final data = Map<String, dynamic>.from(result.data as Map);
      final link = '${data['url']}';
      if (!mounted) return;
      setState(() => _lastLink = link);
      _label.clear();
      await Clipboard.setData(ClipboardData(text: link));
      _message('تم إنشاء رابط تاجر آمن ونسخه للحافظة.');
    } on FirebaseFunctionsException catch (e) {
      _message(e.message ?? 'تعذر إنشاء رابط التاجر.');
    } catch (e) {
      _message('تعذر إنشاء الرابط: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final link = _lastLink;
    if (link == null) return;
    await Clipboard.setData(ClipboardData(text: link));
    _message('تم نسخ الرابط. أرسله للتاجر عبر واتساب أو أي قناة موثوقة.');
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('روابط التجار')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.link, size: 42),
                  const SizedBox(height: 10),
                  const Text('دعوة تاجر حقيقي', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  const Text('أنشئ رابطاً لمرة واحدة. التاجر يفتحه، ينشئ حسابه، ثم يتحول حسابه تلقائياً إلى حساب تاجر معتمد من الدعوة.'),
                  const SizedBox(height: 16),
                  TextField(controller: _label, decoration: const InputDecoration(labelText: 'اسم أو وصف التاجر (اختياري)', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : _createInvite, icon: const Icon(Icons.add_link), label: Text(_busy ? 'جاري الإنشاء...' : 'إنشاء رابط تاجر'))),
                ]),
              ),
            ),
            if (_lastLink != null) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('آخر رابط تم إنشاؤه', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    SelectableText(_lastLink!, style: const TextStyle(fontSize: 13, height: 1.5)),
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _copy, icon: const Icon(Icons.copy), label: const Text('نسخ الرابط'))),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Card(
              elevation: 0,
              child: ListTile(
                leading: Icon(Icons.security_outlined),
                title: Text('الحماية'),
                subtitle: Text('الرابط لا يمنح صلاحيات الإدارة. هو مخصص لتسجيل حساب تاجر فقط، وبعد الاسترداد يسجل النظام العملية في auditLogs.'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
