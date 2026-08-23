import 'package:flutter/foundation.dart';

class WalletModel {
  final double balance;
  final String currency;
  final List<EWallet> eWallets;
  final List<TransactionItem> transactions;

  WalletModel({
    required this.balance,
    required this.currency,
    required this.eWallets,
    required this.transactions,
  });

  factory WalletModel.initial() {
    return WalletModel(
      balance: 150000.0,
      currency: 'ر.ي',
      eWallets: [
        EWallet(name: 'موبايل موني - الكريمي', balance: 45000.0, accountNumber: '771754091', icon: '🏦'),
        EWallet(name: 'القطيبي إكسبريس', balance: 30000.0, accountNumber: '882910234', icon: '💸'),
        EWallet(name: 'بنك التضامن', balance: 75000.0, accountNumber: '554321987', icon: '💳'),
        EWallet(name: 'بنك البسيري للتمويل الأصغر', balance: 12000.0, accountNumber: '332145678', icon: '💰'),
        EWallet(name: 'بنك الأمل للتمويل الأصغر', balance: 25000.0, accountNumber: '221144556', icon: '🌱'),
        EWallet(name: 'بنك سبأ إسلامي', balance: 60000.0, accountNumber: '998877665', icon: '🏛️'),
        EWallet(name: 'بنك الإنشاء والتعمير', balance: 10000.0, accountNumber: '112233445', icon: '🏗️'),
        EWallet(name: 'كاك بنك (التسليف الزراعي)', balance: 18000.0, accountNumber: '665544332', icon: '🌾'),
      ],
      transactions: [
        TransactionItem(title: 'شحن رصيد عبر الكريمي', amount: '+50,000 ر.ي', date: '2026-08-23', isIncome: true),
        TransactionItem(title: 'طلب وجبة - مطاعم مأرب', amount: '-4,500 ر.ي', date: '2026-08-22', isIncome: false),
        TransactionItem(title: 'حجز رحلة (مأرب ➔ عدن)', amount: '-12,000 ر.ي', date: '2026-08-20', isIncome: false),
      ],
    );
  }
}

class EWallet {
  final String name;
  final double balance;
  final String accountNumber;
  final String icon;

  EWallet({required this.name, required this.balance, required this.accountNumber, required this.icon});
}

class TransactionItem {
  final String title;
  final String amount;
  final String date;
  final bool isIncome;

  TransactionItem({required this.title, required this.amount, required this.date, required this.isIncome});
}

class Product {
  final String name;
  final double price;
  final String description;
  final String image;

  Product({required this.name, required this.price, required this.description, required this.image});
}

class Vendor {
  final String name;
  final String rating;
  final String deliveryTime;
  final List<Product> products;

  Vendor({required this.name, required this.rating, required this.deliveryTime, required this.products});
}

// مدير السلة العام
class CartManager extends ChangeNotifier {
  static final CartManager _instance = CartManager._internal();
  factory CartManager() => _instance;
  CartManager._internal();

  final List<Product> _cartItems = [];

  List<Product> get cartItems => _cartItems;

  void addProduct(Product product) {
    _cartItems.add(product);
    notifyListeners();
  }

  void removeProduct(Product product) {
    _cartItems.remove(product);
    notifyListeners();
  }

  void clearCart() {
    _cartItems.clear();
    notifyListeners();
  }

  double get totalPrice {
    double total = 0;
    for (var item in _cartItems) {
      total += item.price;
    }
    return total;
  }
}

