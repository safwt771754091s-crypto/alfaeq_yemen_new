import 'package:flutter/material.dart';

void main() => runApp(const AlfaeqYemenApp());

class Product {
  final String name;
  final String category;
  final int price;
  final String unit;
  const Product(this.name, this.category, this.price, this.unit);
}

const products = <Product>[
  Product('منتج تجريبي 1', 'المتاجر', 0, 'ريال'),
  Product('منتج تجريبي 2', 'المطاعم', 0, 'ريال'),
  Product('منتج تجريبي 3', 'الصيدليات', 0, 'ريال'),
  Product('خدمة حجز تجريبية', 'السفر والفنادق', 0, 'ريال'),
];

class AlfaeqYemenApp extends StatefulWidget {
  const AlfaeqYemenApp({super.key});
  @override
  State<AlfaeqYemenApp> createState() => _AppState();
}

class _AppState extends State<AlfaeqYemenApp> {
  final cart = <Product, int>{};
  void add(Product p) => setState(() => cart[p] = (cart[p] ?? 0) + 1);
  void remove(Product p) => setState(() {
    final n = (cart[p] ?? 0) - 1;
    if (n <= 0) {
      cart.remove(p);
    } else {
      cart[p] = n;
    }
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'الفائق يمن',
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF0B6E4F)),
    home: HomePage(cart: cart, add: add, remove: remove),
  );
}

class HomePage extends StatelessWidget {
  final Map<Product, int> cart;
  final void Function(Product) add;
  final void Function(Product) remove;
  const HomePage({super.key, required this.cart, required this.add, required this.remove});

  @override
  Widget build(BuildContext context) {
    const sections = ['المتاجر', 'المطاعم', 'الصيدليات', 'السفر والفنادق', 'السيارات', 'الخدمات'];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الفائق يمن', style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CartPage(cart: cart, add: add, remove: remove))), icon: const Icon(Icons.shopping_cart_outlined)),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(decoration: InputDecoration(hintText: 'ابحث عن متجر أو خدمة أو منتج', prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none))),
          const SizedBox(height: 16),
          Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), color: const Color(0xFF0B6E4F)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('مرحباً بك في الفائق يمن', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)), SizedBox(height: 8), Text('نسخة تشغيلية أولى: تصفح → اختر → أضف للسلة → أنشئ طلباً.', style: TextStyle(color: Colors.white70))])),
          const SizedBox(height: 24),
          const Text('الأقسام', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: sections.length, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.25), itemBuilder: (_, i) {
            final icons = [Icons.storefront_outlined, Icons.restaurant_outlined, Icons.local_pharmacy_outlined, Icons.flight_takeoff_outlined, Icons.directions_car_outlined, Icons.handyman_outlined];
            return Card(child: InkWell(borderRadius: BorderRadius.circular(12), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SectionPage(title: sections[i], cart: cart, add: add, remove: remove))), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icons[i], size: 38), const SizedBox(height: 10), Text(sections[i], style: const TextStyle(fontWeight: FontWeight.w800))])));
          }),
        ]),
      ),
    );
  }
}

class SectionPage extends StatelessWidget {
  final String title;
  final Map<Product, int> cart;
  final void Function(Product) add;
  final void Function(Product) remove;
  const SectionPage({super.key, required this.title, required this.cart, required this.add, required this.remove});
  @override
  Widget build(BuildContext context) {
    final list = products.where((p) => p.category == title).toList();
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppBar(title: Text(title)), body: list.isEmpty ? const Center(child: Text('القسم جاهز، وسيتم ربط بياناته الحقيقية من Firebase.')) : ListView.builder(padding: const EdgeInsets.all(16), itemCount: list.length, itemBuilder: (_, i) => Card(child: ListTile(title: Text(list[i].name), subtitle: const Text('عنصر اختبار — لا يمثل سعراً أو متجراً حقيقياً'), trailing: FilledButton(onPressed: () { add(list[i]); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت الإضافة إلى السلة'))); }, child: const Text('إضافة'))))));
  }
}

class CartPage extends StatelessWidget {
  final Map<Product, int> cart;
  final void Function(Product) add;
  final void Function(Product) remove;
  const CartPage({super.key, required this.cart, required this.add, required this.remove});
  @override
  Widget build(BuildContext context) {
    final items = cart.entries.toList();
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppBar(title: const Text('السلة')), body: items.isEmpty ? const Center(child: Text('السلة فارغة')) : Column(children: [Expanded(child: ListView.builder(itemCount: items.length, itemBuilder: (_, i) { final e = items[i]; return ListTile(title: Text(e.key.name), subtitle: Text('الكمية: ${e.value}'), trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(onPressed: () => remove(e.key), icon: const Icon(Icons.remove)), IconButton(onPressed: () => add(e.key), icon: const Icon(Icons.add))])); })), Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutPage())), child: const Text('متابعة لإنشاء الطلب'))))]));
  }
}

class CheckoutPage extends StatefulWidget { const CheckoutPage({super.key}); @override State<CheckoutPage> createState() => _CheckoutState(); }
class _CheckoutState extends State<CheckoutPage> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  @override void dispose() { name.dispose(); phone.dispose(); address.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppBar(title: const Text('إنشاء الطلب')), body: ListView(padding: const EdgeInsets.all(16), children: [const Text('بيانات العميل', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 16), TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')), const SizedBox(height: 12), TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')), const SizedBox(height: 12), TextField(controller: address, decoration: const InputDecoration(labelText: 'العنوان')), const SizedBox(height: 24), FilledButton(onPressed: () { if (name.text.trim().isEmpty || phone.text.trim().isEmpty || address.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أكمل بيانات الطلب أولاً'))); return; } Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const OrderCreatedPage())); }, child: const Text('إنشاء الطلب'))]));
}

class OrderCreatedPage extends StatelessWidget { const OrderCreatedPage({super.key}); @override Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.check_circle, size: 80, color: Color(0xFF0B6E4F)), const SizedBox(height: 16), const Text('تم إنشاء الطلب محلياً بنجاح', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900), textAlign: TextAlign.center), const SizedBox(height: 10), const Text('هذه أول دورة تشغيلية حقيقية داخل الواجهة. الخطوة التالية هي حفظ الطلب في Firestore وربطه بحساب التاجر.'), const SizedBox(height: 24), FilledButton(onPressed: () => Navigator.popUntil(context, (r) => r.isFirst), child: const Text('العودة للرئيسية'))])))); }
