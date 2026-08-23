import 'package:flutter/material.dart';
import '../models/wallet_model.dart';

class WalletHistoryScreen extends StatelessWidget {
  const WalletHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = WalletModel.initial();

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل المعاملات المالية', style: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: wallet.transactions.length,
        itemBuilder: (context, index) {
          final tx = wallet.transactions[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 5, offset: const Offset(0, 2)),
              ],
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: tx.isIncome ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                child: Icon(
                  tx.isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                  color: tx.isIncome ? Colors.green : Colors.red,
                ),
              ),
              title: Text(tx.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Text(tx.date, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              trailing: Text(
                tx.amount,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: tx.isIncome ? Colors.green : Colors.red,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

