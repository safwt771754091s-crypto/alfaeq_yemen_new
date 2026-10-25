import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/currency_service.dart';
import '../services/wallet_deposit_service.dart';

const _navy = Color(0xFF0A2540);

/// لوحة اعتماد الإيداعات — master-owner review queue for bank deposits.
/// Approving credits the customer wallet through `wallet_deposit_decide`.
class WalletDepositsReviewPage extends StatefulWidget {
  const WalletDepositsReviewPage({super.key});

  @override
  State<WalletDepositsReviewPage> createState() => _WalletDepositsReviewPageState();
}

class _WalletDepositsReviewPageState extends State<WalletDepositsReviewPage> {
  final _service = WalletDepositService();

  bool _checkingOwner = true;
  bool _isOwner = false;
  bool _loading = true;
  String? _error;
  String _filter = 'pending';
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _checkOwner();
  }

  Future<void> _checkOwner() async {
    final owner = await AuthService().hasOwnerClaim();
    if (!mounted) return;
    setState(() {
      _isOwner = owner;
      _checkingOwner = false;
    });
    if (owner) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.list(status: _filter == 'all' ? null : _filter, limit: 200);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل الطلبات: $e';
        _loading = false;
      });
    }
  }

  Future<void> _decide(Map<String, dynamic> row, bool approve) async {
    final noteController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approve ? 'اعتماد الإيداع وإضافة الرصيد' : 'رفض طلب الإيداع'),
        content: TextField(
          controller: noteController,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: approve ? 'ملاحظة (اختياري)' : 'سبب الرفض',
            border: const OutlineInputBorder(),
          ),
        ),
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
      await _service.decide(depositId: row['id'].toString(), approve: approve, note: note.isEmpty ? null : note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(approve ? 'تم اعتماد الإيداع وإضافة الرصيد.' : 'تم رفض الطلب.')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّر تنفيذ العملية: $e')));
    }
  }

  Future<void> _openReceipt(Map<String, dynamic> row) async {
    final path = (row['receipt_url'] ?? '').toString();
    if (path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد سند مرفق لهذا الطلب.')));
      return;
    }
    final url = await _service.receiptUrl(path);
    if (!mounted) return;
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر فتح السند.')));
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('اعتماد الإيداعات', style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            if (_isOwner) IconButton(onPressed: _load, tooltip: 'تحديث', icon: const Icon(Icons.refresh)),
          ],
        ),
        body: _checkingOwner
            ? const Center(child: CircularProgressIndicator())
            : !_isOwner
                ? _forbidden()
                : Column(
                    children: [
                      _filterBar(),
                      Expanded(child: _body()),
                    ],
                  ),
      ),
    );
  }

  Widget _filterBar() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(
          spacing: 8,
          children: [
            _chip('pending', 'قيد المراجعة'),
            _chip('approved', 'معتمدة'),
            _chip('rejected', 'مرفوضة'),
            _chip('all', 'الكل'),
          ],
        ),
      );

  Widget _chip(String value, String label) => ChoiceChip(
        label: Text(label),
        selected: _filter == value,
        onSelected: (_) {
          setState(() => _filter = value);
          _load();
        },
      );

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')),
          ]),
        ),
      );
    }
    if (_rows.isEmpty) {
      return const Center(child: Text('لا توجد طلبات في هذه الحالة.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) => _depositCard(_rows[i]),
      ),
    );
  }

  Widget _depositCard(Map<String, dynamic> row) {
    final status = (row['status'] ?? 'pending').toString();
    final currency = (row['currency'] ?? 'YER').toString();
    final amount = num.tryParse(row['amount']?.toString() ?? '0') ?? 0;
    final hasReceipt = ((row['receipt_url'] ?? '').toString()).isNotEmpty;
    final reviewedBy = (row['reviewed_by'] ?? '').toString();
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  CurrencyService.instance.formatNative(amount, currency),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: _navy),
                ),
              ),
              _statusBadge(status),
            ],
          ),
          const SizedBox(height: 8),
          Text('المستخدم: ${row['uid']}', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
          Text('رقم الإيصال: ${row['receipt_ref']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('التاريخ: ${(row['created_at'] ?? '').toString().replaceFirst('T', ' ').split('.').first}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          if (reviewedBy.isNotEmpty)
            Text('راجعه: $reviewedBy', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          if (((row['review_note'] ?? '').toString()).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('ملاحظة: ${row['review_note']}', style: const TextStyle(fontStyle: FontStyle.italic)),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (hasReceipt)
                TextButton.icon(
                  onPressed: () => _openReceipt(row),
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: const Text('عرض السند'),
                ),
              const Spacer(),
              if (status == 'pending') ...[
                OutlinedButton(
                  onPressed: () => _decide(row, false),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('رفض'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _decide(row, true),
                  child: const Text('اعتماد'),
                ),
              ],
            ],
          ),
        ]),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final (label, color) = switch (status) {
      'approved' => ('معتمد', Colors.green),
      'rejected' => ('مرفوض', Colors.red),
      _ => ('قيد المراجعة', Colors.orange),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }

  Widget _forbidden() => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 56, color: Colors.grey),
              SizedBox(height: 12),
              Text('هذه الصفحة مخصّصة لحساب المالك فقط.', textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}
