class WalletModel {
  final double balance;
  final String currency;
  final List<TransactionItem> transactions;

  WalletModel({
    required this.balance,
    required this.currency,
    required this.transactions,
  });

  factory WalletModel.initial() {
    return WalletModel(
      balance: 150000.0,
      currency: 'ر.ي',
      transactions: [
        TransactionItem(title: 'شحن رصيد محفظة الفائق', amount: '+50,000 ر.ي', date: '2026-08-23', isIncome: true),
        TransactionItem(title: 'طلب وجبة - المطاعم', amount: '-4,500 ر.ي', date: '2026-08-22', isIncome: false),
        TransactionItem(title: 'حجز رحلة (مأرب ➔ عدن)', amount: '-12,000 ر.ي', date: '2026-08-20', isIncome: false),
      ],
    );
  }
}

class TransactionItem {
  final String title;
  final String amount;
  final String date;
  final bool isIncome;

  TransactionItem({
    required this.title,
    required this.amount,
    required this.date,
    required this.isIncome,
  });
}

