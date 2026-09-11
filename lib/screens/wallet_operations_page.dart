import 'package:flutter/material.dart';

import '../services/wallet_service.dart';

class WalletOperationsPage extends StatefulWidget {
  const WalletOperationsPage({super.key});

  @override
  State<WalletOperationsPage> createState() => _WalletOperationsPageState();
}

class _WalletOperationsPageState extends State<WalletOperationsPage> {
  final _recipientController = TextEditingController();
  final _amountController = TextEditingController();
  bool _busy = false;
  String _mode = 'transfer';

  @override
  void dispose() {
    _recipientController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      _message('أدخل مبلغاً صحيحاً أكبر من صفر.');
      return;
    }
    if (_mode == 'transfer' && _recipientController.text.trim().isEmpty) {
      _message('أدخل معرف المستفيد.');
      return;
    }
    setState(() => _busy = true);
    try {
      final service = WalletService();
      String operationId;
      if (_mode == 'transfer') {
        operationId = await service.requestTransfer(
          recipientUid: _recipientController.text,
          amount: amount,
        );
      } else if (_mode == 'deposit') {
        operationId = await service.requestDeposit(amount: amount);
      } else {
        operationId = await service.requestWithdraw(amount: amount);
      }
      if (!mounted) return;
      _amountController.clear();
      _recipientController.clear();
      _message('تم إنشاء الطلب بنجاح. رقم العملية: $operationId');
    } catch (error) {
      if (mounted) _message('تعذر إنشاء الطلب: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('عمليات المحفظة', style: TextStyle(fontWeight: FontWeight.w900)),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              elevation: 0,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.security_outlined, color: Color(0xFF0B6E4F)),
                    SizedBox(width: 10),
                    Expanded(child: Text('الطلبات تُنشأ فقط. الرصيد وسجل القيود لا يتم تعديلهما من جهاز العميل.')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'transfer', icon: Icon(Icons.send_outlined), label: Text('تحويل')),
                ButtonSegment(value: 'deposit', icon: Icon(Icons.add_circle_outline), label: Text('إيداع')),
                ButtonSegment(value: 'withdraw', icon: Icon(Icons.remove_circle_outline), label: Text('سحب')),
              ],
              selected: {_mode},
              onSelectionChanged: (value) => setState(() => _mode = value.first),
            ),
            const SizedBox(height: 18),
            if (_mode == 'transfer') ...[
              TextField(
                controller: _recipientController,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'معرف المستفيد',
                  hintText: 'UID',
                  prefixIcon: Icon(Icons.person_search_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'المبلغ',
                suffixText: 'YER',
                prefixIcon: Icon(Icons.payments_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_mode == 'transfer' ? Icons.send : Icons.check_circle_outline),
              label: Text(_busy ? 'جارٍ إنشاء الطلب...' : 'إرسال الطلب'),
            ),
            const SizedBox(height: 14),
            const Text(
              'الإيداع والسحب يبقيان بحالة انتظار التحقق حتى يتم اعتماد قناة الدفع الموثوقة. التحويل الداخلي فقط يمكن للخادم إكماله عند تحقق الرصيد وصلاحية المحافظ.',
              style: TextStyle(color: Colors.black54, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
