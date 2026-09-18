import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class WhatsAppAutomationPage extends StatefulWidget {
  const WhatsAppAutomationPage({super.key});
  @override State<WhatsAppAutomationPage> createState() => _WhatsAppAutomationPageState();
}

class _WhatsAppAutomationPageState extends State<WhatsAppAutomationPage> {
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  bool _loading = false;

  Future<List<Map<String, dynamic>>> _loadImports() async {
    final result = await _functions.httpsCallable('listWhatsAppProductImports').call({'limit': 50});
    return ((result.data as Map?)?['imports'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _confirm(Map<String, dynamic> item) async {
    final name = TextEditingController(text: (item['parsed']?['name'] ?? '').toString());
    final price = TextEditingController(text: (item['parsed']?['price'] ?? '').toString());
    final stock = TextEditingController(text: (item['parsed']?['stock'] ?? '0').toString());
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اعتماد منتج واتساب'),
        content: SingleChildScrollView(child: Column(children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم المنتج')),
          TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر ر.ي')),
          TextField(controller: stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المخزون')),
          const SizedBox(height: 10),
          const Text('سيتم إنشاء المنتج كمُسودة ما لم يكن النشر التلقائي مفعّلًا.', style: TextStyle(fontSize: 12)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, {'name': name.text, 'price': price.text, 'stock': stock.text}), child: const Text('إنشاء المنتج')),
        ],
      ),
    );
    if (values == null) return;
    setState(() => _loading = true);
    try {
      await _functions.httpsCallable('confirmWhatsAppProductImport').call({
        'importId': item['id'], 'name': values['name'],
        'price': double.tryParse(values['price'] ?? ''),
        'stock': int.tryParse(values['stock'] ?? ''), 'publish': false,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إنشاء المنتج بأمان من رسالة واتساب.')));
      setState(() {});
    } on FirebaseFunctionsException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل اعتماد المنتج: ' + (e.message ?? e.code))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('أتمتة واتساب', style: TextStyle(fontWeight: FontWeight.w900))),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _loadImports(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('تعذر تحميل رسائل واتساب: ' + snapshot.error.toString())));
            final items = snapshot.data ?? [];
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('WhatsApp Business → الفائق يمن', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  const Text('Webhook رسمي يستقبل رسائل التجار، يربط رقم التاجر بالمتجر، يستخرج بيانات المنتج ويضعها في مسودة آمنة مع سجل تدقيق.'),
                  const SizedBox(height: 12),
                  const SelectableText('Webhook: https://us-central1-alfaeq-yemen-fed37.cloudfunctions.net/whatsappWebhook', style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ]))),
                const SizedBox(height: 14),
                if (_loading) const LinearProgressIndicator(),
                if (items.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('لا توجد واردات واتساب بعد. بعد ربط WhatsApp Business وإرسال رسالة للرقم المرتبط بمتجر، ستظهر هنا.')))
                else
                  ...items.map((item) {
                    final parsed = Map<String, dynamic>.from(item['parsed'] as Map? ?? {});
                    final status = (item['status'] ?? 'unknown').toString();
                    return Card(child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.message_outlined)),
                      title: Text((parsed['name'] ?? item['text'] ?? 'رسالة واتساب').toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('الحالة: ' + status + '\nالهاتف: ' + (item['phone'] ?? '').toString()),
                      isThreeLine: true,
                      trailing: status == 'pending_confirmation' ? IconButton(icon: const Icon(Icons.check_circle_outline), onPressed: () => _confirm(item)) : null,
                    ));
                  }),
              ],
            );
          },
        ),
      ),
    );
  }
}