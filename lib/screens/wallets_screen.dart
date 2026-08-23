import 'package:flutter/material.dart';

class WalletsScreen extends StatelessWidget {
  const WalletsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المحافظ الإلكترونية والبنوك', style: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1A365D),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('إجمالي رصيد التطبيق والمحافظ المتاحة', style: TextStyle(color: Colors.white70, fontSize: 14)),
                SizedBox(height: 8),
                Text('150,000 ر.ي', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('اختر المحافظ البنكية والإلكترونية للشحن:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _buildWalletOption(context, 'محافظ الكريمي الإسلامي', 'رقم الحساب: 123456789', Icons.account_balance, Colors.orange),
          _buildWalletOption(context, 'محفظة جيب (Jeep)', 'رقم الحساب: 770000000', Icons.phone_android, Colors.blue),
          _buildWalletOption(context, 'محفظة سبأكاش (SabaCash)', 'رقم الحساب: 710000000', Icons.payment, Colors.green),
          _buildWalletOption(context, 'التحويل المباشر - بنك القطيبي', 'رقم الحساب: 987654321', Icons.account_balance_wallet, Colors.indigo),
        ],
      ),
    );
  }

  Widget _buildWalletOption(BuildContext context, String title, String subtitle, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 5, offset: const Offset(0, 2))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ],
          ),
          ElevatedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('تم اختيار $title للشحن أو الدفع')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('شحن / دفع'),
          )
        ],
      ),
    );
  }
}
	

