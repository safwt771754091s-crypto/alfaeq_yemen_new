import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class WalletTopupScreen extends StatefulWidget {
  const WalletTopupScreen({super.key});
  @override
  State<WalletTopupScreen> createState() => _WalletTopupScreenState();
}

class _WalletTopupScreenState extends State<WalletTopupScreen> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  String? _selectedMethod;
  String _service = 'رصيد يمن موبايل';
  String _status = 'اختر وسيلة التحويل ثم سجّل طلب الشحن في Firestore.';
  bool _busy = false;

  final services = const [
    'رصيد يمن موبايل',
    'رصيد YOU',
    'رصيد سبأفون',
    'إنترنت يمن موبايل',
    'إنترنت YOU',
    'إنترنت سبأفون',
    'شحن خدمات رقمية / اجتماعية',
  ];

  Future<void> _submitTopup() async {
    final user = FirebaseAuth.instance.currentUser;
    final amount = double.tryParse(_amount.text.trim());
    if (user == null) {
      setState(() => _status = 'يجب تسجيل الدخول أولاً.');
      return;
    }
    if (_selectedMethod == null || amount == null || amount <= 0) {
      setState(() => _status = 'اختر وسيلة الدفع وأدخل مبلغاً صحيحاً.');
      return;
    }
    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance.collection('walletTopups').add({
        'userId': user.uid,
        'userEmail': user.email ?? '',
        'paymentMethodId': _selectedMethod,
        'service': _service,
        'amount': amount,
        'reference': _reference.text.trim(),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _amount.clear();
      _reference.clear();
      setState(() => _status = 'تم تسجيل طلب الشحن الحقيقي في قاعدة البيانات. سيظهر للإدارة للمراجعة والاعتماد.');
    } catch (e) {
      setState(() => _status = 'تعذر تسجيل الطلب: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('شحن المحفظة والخدمات الرقمية')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('وسيلة التحويل المتاحة من الإدارة', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('paymentMethods').where('active', isEqualTo: true).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text('خطأ في تحميل وسائل الدفع: ${snapshot.error}');
              final docs = snapshot.data?.docs ?? const [];
              if (docs.isEmpty) return const Text('لم تضف الإدارة وسيلة دفع بعد.');
              _selectedMethod ??= docs.first.id;
              return DropdownButtonFormField<String>(
                value: docs.any((d) => d.id == _selectedMethod) ? _selectedMethod : docs.first.id,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: docs.map((doc) {
                  final data = doc.data();
                  return DropdownMenuItem(value: doc.id, child: Text('${data['name'] ?? ''} — ${data['account'] ?? ''}'));
                }).toList(),
                onChanged: (v) => setState(() => _selectedMethod = v),
              );
            },
          ),
          const SizedBox(height: 16),
          const Text('الخدمة التي تريد شحنها', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _service,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: services.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (v) => setState(() => _service = v!),
          ),
          const SizedBox(height: 16),
          TextField(controller: _amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المبلغ بالريال اليمني', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _reference, decoration: const InputDecoration(labelText: 'رقم العملية / مرجع التحويل', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          SizedBox(height: 48, child: ElevatedButton.icon(onPressed: _busy ? null : _submitTopup, icon: const Icon(Icons.send), label: const Text('إرسال طلب الشحن'))),
          const SizedBox(height: 16),
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)), child: Text(_status)),
          const SizedBox(height: 20),
          const Text('مهم: هذا يربط دورة طلب الشحن بقاعدة البيانات فعلياً. تنفيذ الخصم/الإيداع المصرفي أو شحن الاتصالات يحتاج API أو اتفاقاً رسمياً مع مزود الخدمة، لذلك لا ندّعي وجود تحويل مالي حي بدون اعتماد المزود.'),
        ],
      ),
    ),
  );
}
