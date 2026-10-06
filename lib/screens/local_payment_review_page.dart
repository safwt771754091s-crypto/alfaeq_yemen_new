import 'package:flutter/material.dart';

import '../services/currency_service.dart';
import '../services/order_service.dart';

/// Staff review of bank / e-wallet transfer receipts. Approving marks the order
/// paid through the same server lifecycle as card payments.
class LocalPaymentReviewPage extends StatefulWidget {
  const LocalPaymentReviewPage({super.key});
  @override
  State<LocalPaymentReviewPage> createState() => _LocalPaymentReviewPageState();
}

class _LocalPaymentReviewPageState extends State<LocalPaymentReviewPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await OrderService(preferSupabase: true).pendingLocalPayments();
      if (mounted) setState(() { _rows = rows; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'تعذر تحميل الطلبات: $e'; _loading = false; });
    }
  }

  Future<void> _decide(Map<String, dynamic> row, bool approve) async {
    final noteController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approve ? 'تأكيد استلام الدفعة' : 'رفض إشعار الحوالة'),
        content: TextField(controller: noteController, maxLines: 2, decoration: InputDecoration(labelText: approve ? 'ملاحظة (اختياري)' : 'سبب الرفض', border: const OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('تأكيد')),
        ],
      ),
    );
    final note = noteController.text.trim();
    noteController.dispose();
    if (confirm != true) return;
    try {
      await OrderService(preferSupabase: true).approveLocalPayment(
        orderId: row['id'].toString(), approve: approve, note: note.isEmpty ? null : note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(approve ? 'تم تأكيد الدفع وتحديث الطلب.' : 'تم رفض الإشعار.')));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تنفيذ العملية: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('مراجعة الحوالات المحلية', style: TextStyle(fontWeight: FontWeight.w900)),
            actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
                  : _rows.isEmpty
                      ? const Center(child: Text('لا توجد حوالات بانتظار المراجعة.'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final row = _rows[index];
                            final meta = Map<String, dynamic>.from((row['metadata'] as Map?) ?? const {});
                            final amount = num.tryParse(row['total']?.toString() ?? '') ?? 0;
                            final currency = (row['currency'] ?? 'USD').toString();
                            return Card(
                              elevation: 0,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                  Text('طلب: ${row['id']}', style: const TextStyle(fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 4),
                                  Text('المبلغ: ${CurrencyService.instance.formatNative(amount, currency)}'),
                                  Text('المرجع: ${meta['transfer_reference'] ?? '-'}'),
                                  if ((meta['transfer_note'] ?? '').toString().isNotEmpty) Text('ملاحظة العميل: ${meta['transfer_note']}'),
                                  const SizedBox(height: 8),
                                  Row(children: [
                                    Expanded(child: OutlinedButton.icon(onPressed: () => _decide(row, false), icon: const Icon(Icons.close), label: const Text('رفض'))),
                                    const SizedBox(width: 8),
                                    Expanded(child: FilledButton.icon(onPressed: () => _decide(row, true), icon: const Icon(Icons.check), label: const Text('تأكيد الدفع'))),
                                  ]),
                                ]),
                              ),
                            );
                          },
                        ),
        ),
      );
}
