import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/currency_service.dart';
import '../services/wallet_deposit_service.dart';

const _blue = Color(0xFF0D6EFD);
const _navy = Color(0xFF0A2540);

/// إيداع الرصيد — shows the three official Al-Kuraimi accounts and lets the
/// user submit a transfer receipt (reference number and optional image).
class WalletDepositPage extends StatefulWidget {
  const WalletDepositPage({super.key});

  @override
  State<WalletDepositPage> createState() => _WalletDepositPageState();
}

class _WalletDepositPageState extends State<WalletDepositPage> {
  final _service = WalletDepositService();
  final _amountController = TextEditingController();
  final _refController = TextEditingController();

  bool _loadingAccounts = true;
  String? _accountsError;
  List<Map<String, dynamic>> _accounts = const [];
  String _currency = 'YER';

  Uint8List? _receiptBytes;
  String? _receiptName;

  bool _submitting = false;
  List<Map<String, dynamic>> _myDeposits = const [];

  @override
  void initState() {
    super.initState();
    _loadAccounts();
    _loadMyDeposits();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _refController.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    setState(() {
      _loadingAccounts = true;
      _accountsError = null;
    });
    try {
      final rows = await _service.bankAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = rows;
        _loadingAccounts = false;
        if (rows.isNotEmpty && !rows.any((r) => r['currency'] == _currency)) {
          _currency = (rows.first['currency'] ?? 'YER').toString();
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _accountsError = 'تعذّر تحميل الحسابات البنكية، حاول لاحقاً.';
        _loadingAccounts = false;
      });
    }
  }

  Future<void> _loadMyDeposits() async {
    try {
      final rows = await _service.list(status: null, limit: 50);
      if (mounted) setState(() => _myDeposits = rows);
    } catch (_) {
      // The history is best-effort; the form still works.
    }
  }

  Map<String, dynamic>? get _selectedAccount {
    for (final a in _accounts) {
      if (a['currency'] == _currency) return a;
    }
    return _accounts.isEmpty ? null : _accounts.first;
  }

  Future<void> _pickReceipt() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _receiptBytes = bytes;
        _receiptName = file.name;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر اختيار الملف')),
        );
      }
    }
  }

  Future<void> _submit() async {
    final amount = num.tryParse(_amountController.text.trim());
    final ref = _refController.text.trim();
    if (amount == null || amount <= 0) {
      _snack('أدخل مبلغاً صحيحاً أكبر من صفر.');
      return;
    }
    if (ref.isEmpty) {
      _snack('أدخل رقم الإيصال الصادر من الكريمي.');
      return;
    }
    setState(() => _submitting = true);
    try {
      String? path;
      if (_receiptBytes != null) {
        final name = _receiptName ?? 'receipt.jpg';
        final ext = name.contains('.') ? name.split('.').last : 'jpg';
        path = await _service.uploadReceipt(_receiptBytes!, ext);
      }
      await _service.create(
        currency: _currency,
        amount: amount,
        receiptRef: ref,
        receiptPath: path,
        bankAccountId: _selectedAccount?['id']?.toString(),
      );
      if (!mounted) return;
      _amountController.clear();
      _refController.clear();
      setState(() {
        _receiptBytes = null;
        _receiptName = null;
        _submitting = false;
      });
      _snack('تم إرسال طلب الإيداع، بانتظار مراجعة إدارة الفائق يمن.');
      _loadMyDeposits();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack('تعذّر إرسال الطلب: $e');
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إيداع الرصيد', style: TextStyle(fontWeight: FontWeight.w900)),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _intro(),
            const SizedBox(height: 16),
            const _SectionTitle('حسابات بنك الكريمي الرسمية'),
            const SizedBox(height: 8),
            if (_loadingAccounts)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (_accountsError != null)
              _errorBox(_accountsError!)
            else
              ..._accounts.map(_accountCard),
            const SizedBox(height: 20),
            const _SectionTitle('بيانات الحوالة'),
            const SizedBox(height: 8),
            _currencySelector(),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: const InputDecoration(
                labelText: 'المبلغ المحوَّل',
                prefixIcon: Icon(Icons.payments_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _refController,
              decoration: const InputDecoration(
                labelText: 'رقم الإيصال / السند من الكريمي',
                prefixIcon: Icon(Icons.receipt_long_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            _receiptPicker(),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send),
                label: Text(_submitting ? 'جارٍ الإرسال…' : 'إرسال طلب الإيداع', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 24),
            const _SectionTitle('طلباتي السابقة'),
            const SizedBox(height: 8),
            _depositHistory(),
          ],
        ),
      ),
    );
  }

  Widget _intro() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFF1F6FF), borderRadius: BorderRadius.circular(12)),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: _blue),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'حوّل المبلغ إلى أحد الحسابات الرسمية أدناه، ثم أدخل رقم الإيصال وأرفق صورة السند. '
                'سيراجع فريق الفائق يمن الطلب ويُضاف الرصيد إلى محفظتك بعد الاعتماد.',
                style: TextStyle(height: 1.5),
              ),
            ),
          ],
        ),
      );

  Widget _accountCard(Map<String, dynamic> a) {
    final currency = (a['currency'] ?? '').toString();
    final number = (a['account_number'] ?? '').toString();
    final bank = (a['bank_name'] ?? 'بنك الكريمي').toString();
    final name = (a['account_name'] ?? '').toString();
    final selected = currency == _currency;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? _blue : Colors.grey.shade300, width: selected ? 1.6 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _currencyBadge(currency),
                const SizedBox(width: 8),
                Expanded(child: Text(bank, style: const TextStyle(fontWeight: FontWeight.w900, color: _navy))),
                if (selected) const Icon(Icons.check_circle, color: _blue, size: 20),
              ],
            ),
            const SizedBox(height: 10),
            if (name.isNotEmpty) _kv('اسم الحساب', name),
            _kv('رقم الحساب', number, copyable: true),
          ],
        ),
      ),
    );
  }

  Widget _currencyBadge(String currency) {
    final label = switch (currency) {
      'YER' => 'ريال يمني',
      'SAR' => 'ريال سعودي',
      'USD' => 'دولار أمريكي',
      _ => currency,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: _blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: Text('$label · $currency', style: const TextStyle(color: _blue, fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }

  Widget _kv(String label, String value, {bool copyable = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            SizedBox(width: 96, child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13))),
            Expanded(
              child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.5)),
            ),
            if (copyable)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'نسخ',
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: value));
                  _snack('تم نسخ رقم الحساب');
                },
              ),
          ],
        ),
      );

  Widget _currencySelector() => Wrap(
        spacing: 8,
        children: _accounts.map((a) {
          final currency = (a['currency'] ?? '').toString();
          return ChoiceChip(
            label: Text(currency),
            selected: _currency == currency,
            onSelected: (_) => setState(() => _currency = currency),
          );
        }).toList(),
      );

  Widget _receiptPicker() => OutlinedButton.icon(
        onPressed: _pickReceipt,
        icon: const Icon(Icons.attach_file),
        label: Text(
          _receiptName == null ? 'إرفاق صورة السند (اختياري)' : 'مرفق: $_receiptName',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          alignment: Alignment.centerRight,
        ),
      );

  Widget _depositHistory() {
    if (_myDeposits.isEmpty) {
      return const Card(
        elevation: 0,
        child: ListTile(title: Text('لا توجد طلبات إيداع بعد.'), leading: Icon(Icons.history)),
      );
    }
    return Column(
      children: _myDeposits.map((d) {
        final status = (d['status'] ?? 'pending').toString();
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              status == 'approved' ? Icons.check_circle : status == 'rejected' ? Icons.cancel : Icons.hourglass_top,
              color: status == 'approved' ? Colors.green : status == 'rejected' ? Colors.red : Colors.orange,
            ),
            title: Text('${d['amount']} ${d['currency']}', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('إيصال: ${d['receipt_ref']} · ${_statusLabel(status)}'),
            trailing: Text(
              CurrencyService.instance.formatNative(
                num.tryParse(d['amount']?.toString() ?? '0') ?? 0,
                (d['currency'] ?? 'YER').toString(),
              ),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        );
      }).toList(),
    );
  }

  static String _statusLabel(String status) => switch (status) {
        'approved' => 'معتمد',
        'rejected' => 'مرفوض',
        _ => 'قيد المراجعة',
      };

  Widget _errorBox(String text) => Card(
        elevation: 0,
        color: const Color(0xFFFFF3F3),
        child: ListTile(
          leading: const Icon(Icons.error_outline, color: Colors.red),
          title: Text(text),
          trailing: TextButton(onPressed: _loadAccounts, child: const Text('إعادة المحاولة')),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _navy),
      );
}
