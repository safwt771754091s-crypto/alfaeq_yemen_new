import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/wallet_service.dart';
import 'wallet_operations_page.dart';

class RealWalletPage extends StatefulWidget {
  const RealWalletPage({super.key});

  @override
  State<RealWalletPage> createState() => _RealWalletPageState();
}

class _RealWalletPageState extends State<RealWalletPage> {
  final WalletService service = WalletService();
  bool initializing = false;

  Future<void> _initialize() async {
    setState(() => initializing = true);
    try {
      await service.initializeZeroWallet();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إنشاء محفظتك الآمنة برصيد ابتدائي 0 ريال.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إنشاء المحفظة: $error')));
    } finally {
      if (mounted) setState(() => initializing = false);
    }
  }

  void _openOperations() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletOperationsPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('محفظتي', style: TextStyle(fontWeight: FontWeight.w900))),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: service.watchWallet(),
          builder: (context, walletSnapshot) {
            if (walletSnapshot.hasError) return _error('تعذر الوصول إلى المحفظة.');
            if (walletSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            final wallet = walletSnapshot.data;
            if (wallet == null || !wallet.exists) return _notInitialized();
            final data = wallet.data() ?? const <String, dynamic>{};
            final available = data['availableBalance'] is num ? (data['availableBalance'] as num).toDouble() : 0.0;
            final reserved = data['reservedBalance'] is num ? (data['reservedBalance'] as num).toDouble() : 0.0;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
              children: [
                _balanceCard(available, reserved, '${data['currency'] ?? 'YER'}'),
                const SizedBox(height: 14),
                FilledButton.icon(onPressed: _openOperations, icon: const Icon(Icons.swap_horiz), label: const Text('تحويل / إيداع / سحب')),
                const SizedBox(height: 16),
                const _SecurityCard(),
                const SizedBox(height: 18),
                const Text('آخر المعاملات', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: service.watchTransactions(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) return _error('لا يمكن تحميل سجل المعاملات حالياً.');
                    if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
                    final docs = snapshot.data?.docs ?? const [];
                    if (docs.isEmpty) return const Card(elevation: 0, child: Padding(padding: EdgeInsets.all(18), child: Text('لا توجد معاملات بعد.')));
                    return Column(children: docs.map((doc) => _TransactionTile(data: doc.data())).toList());
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _notInitialized() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.account_balance_wallet_outlined, size: 52, color: Color(0xFF0B6E4F)),
                const SizedBox(height: 12),
                const Text('محفظتك جاهزة للإنشاء', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 7),
                const Text('سيتم إنشاء محفظة برصيد صفر. الإيداع والسحب والتحويل لا يتم تنفيذها من التطبيق مباشرة؛ ستتم عبر طبقة دفع موثوقة ومصرح بها.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, height: 1.45)),
                const SizedBox(height: 18),
                FilledButton.icon(onPressed: initializing ? null : _initialize, icon: initializing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_card_outlined), label: const Text('إنشاء المحفظة')),
              ]),
            ),
          ),
        ),
      );

  Widget _balanceCard(double available, double reserved, String currency) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF0B6E4F), Color(0xFF124E78)]),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [Icon(Icons.account_balance_wallet_outlined, color: Colors.white), SizedBox(width: 8), Text('الرصيد المتاح', style: TextStyle(color: Colors.white70))]),
          const SizedBox(height: 9),
          Text('${available.toStringAsFixed(0)} $currency', style: const TextStyle(color: Colors.white, fontSize: 31, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text('محجوز: ${reserved.toStringAsFixed(0)} $currency', style: const TextStyle(color: Colors.white70)),
        ]),
      );

  Widget _error(String text) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(text, textAlign: TextAlign.center)));
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard();
  @override
  Widget build(BuildContext context) => Card(elevation: 0, child: ListTile(leading: const Icon(Icons.verified_user_outlined, color: Color(0xFF0B6E4F)), title: const Text('حماية مالية', style: TextStyle(fontWeight: FontWeight.w900)), subtitle: const Text('الرصيد لا يمكن تعديله من واجهة العميل، وسجل المعاملات للقراءة فقط. عمليات التحويل ستنفذ عبر طبقة خادمية موثوقة.')));
}

class _TransactionTile extends StatelessWidget {
  final Map<String, dynamic> data;
  const _TransactionTile({required this.data});
  @override
  Widget build(BuildContext context) {
    final amount = data['amount'];
    final type = '${data['type'] ?? 'transaction'}';
    final status = '${data['status'] ?? 'pending'}';
    return Card(elevation: 0, child: ListTile(leading: CircleAvatar(backgroundColor: const Color(0xFFE7F3EE), child: Icon(type.contains('credit') ? Icons.arrow_downward : Icons.arrow_upward, color: const Color(0xFF0B6E4F))), title: Text(amount is num ? '${amount.toString()} ${data['currency'] ?? 'YER'}' : 'معاملة مالية', style: const TextStyle(fontWeight: FontWeight.w900)), subtitle: Text('${data['description'] ?? 'معاملة محفظة'} • $status')));
  }
}
