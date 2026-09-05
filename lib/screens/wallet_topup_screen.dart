import 'package:flutter/material.dart';

class WalletTopupScreen extends StatefulWidget {
  const WalletTopupScreen({super.key});
  @override State<WalletTopupScreen> createState() => _WalletTopupScreenState();
}

class _WalletTopupScreenState extends State<WalletTopupScreen> {
  final _amount = TextEditingController();
  String _source = 'تحويل بنكي';
  String _service = 'رصيد يمن موبايل';
  String _status = 'وضع الاختبار — لا يتم خصم أموال حقيقية';

  final banks = const ['البنك اليمني للإنشاء والتعمير', 'البنك الأهلي اليمني', 'بنك اليمن والكويت', 'بنك التضامن', 'بنك سبأ الإسلامي', 'بنك الكريمي الإسلامي', 'بنك القطيبي الإسلامي', 'بنك اليمن الدولي', 'بنك الأمل للتمويل الأصغر', 'مصرف اليمن والبحرين الشامل'];
  final services = const ['رصيد يمن موبايل', 'رصيد YOU', 'رصيد سبأفون', 'إنترنت يمن موبايل', 'إنترنت YOU', 'إنترنت سبأفون', 'شحن خدمات رقمية / اجتماعية'];

  void _runTest() {
    final amount = int.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _status = 'أدخل مبلغاً صحيحاً للتجربة');
      return;
    }
    setState(() => _status = 'نجح الاختبار التجريبي: $_service بقيمة $amount ر.ي عبر $_source');
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('شحن المحفظة والخدمات الرقمية')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('مصدر تغذية المحفظة', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(value: _source, decoration: const InputDecoration(border: OutlineInputBorder()), items: [...banks.map((b) => DropdownMenuItem(value: b, child: Text(b))), const DropdownMenuItem(value: 'محفظة يمنية أخرى', child: Text('محفظة يمنية أخرى'))], onChanged: (v) => setState(() => _source = v!)),
        const SizedBox(height: 16),
        const Text('الخدمة التي تريد شحنها', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(value: _service, decoration: const InputDecoration(border: OutlineInputBorder()), items: services.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) => setState(() => _service = v!)),
        const SizedBox(height: 16),
        TextField(controller: _amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المبلغ بالريال اليمني', border: OutlineInputBorder())),
        const SizedBox(height: 16),
        SizedBox(height: 48, child: ElevatedButton.icon(onPressed: _runTest, icon: const Icon(Icons.bolt), label: const Text('تنفيذ الاختبار التجريبي'))),
        const SizedBox(height: 16),
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)), child: Text(_status)),
        const SizedBox(height: 20),
        const Text('قبل الإطلاق: كل بنك أو مزود شحن يحتاج قناة/API أو آلية تحويل معتمدة. هذه الشاشة لا تدّعي وجود ربط مصرفي حي بدون بيانات اعتماد رسمية.'),
      ]),
    ),
  );
}
