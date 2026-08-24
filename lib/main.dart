import 'package:flutter/material.dart';

void main() {
  runApp(const AlfaeqYemenApp());
}

class AlfaeqYemenApp extends StatelessWidget {
  const AlfaeqYemenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'الفائق يمن',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF7FAFC),
        fontFamily: 'sans-serif',
      ),
      home: const HomeScreen(),
    );
  }
}

class CartModel {
  static final List<Map<String, dynamic>> items = [];
  static double get totalAmount {
    double sum = 0;
    for (var item in items) {
      sum += (item['price'] as num).toDouble();
    }
    return sum;
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> categories = [
      {'name': 'الصيدليات والأدوية', 'icon': Icons.local_hospital, 'color': Colors.teal},
      {'name': 'الرحلات والسفر', 'icon': Icons.directions_bus, 'color': Colors.orange},
      {'name': 'السوبرماركت', 'icon': Icons.shopping_basket, 'color': Colors.green},
      {'name': 'المطاعم والوجبات', 'icon': Icons.restaurant, 'color': Colors.red},
      {'name': 'الشحن بين المدن', 'icon': Icons.local_shipping, 'color': Colors.brown},
      {'name': 'توصيل مشاوير', 'icon': Icons.motorcycle, 'color': Colors.blue},
      {'name': 'الملابس والأزياء', 'icon': Icons.checkroom, 'color': Colors.pink},
      {'name': 'أدوات التجميل', 'icon': Icons.face, 'color': Colors.purple},
      {'name': 'المراكز الطبية', 'icon': Icons.medical_services, 'color': Colors.redAccent},
      {'name': 'حجز الفنادق', 'icon': Icons.hotel, 'color': Colors.indigo},
      {'name': 'التوصيل والمالية', 'icon': Icons.account_balance_wallet, 'color': Colors.amber},
      {'name': 'كل الخدمات', 'icon': Icons.grid_view, 'color': Colors.grey},
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A365D),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الفائق يمن', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            Text('الفائق.. يوصل لبي ما يوصل', style: TextStyle(color: Colors.white70, fontSize: 10)),
          ],
        ),
        actions: [
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.shopping_cart, color: Colors.white),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                    constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                    child: Text('${CartModel.items.length}', style: const TextStyle(color: Colors.white, fontSize: 8), textAlign: TextAlign.center),
                  ),
                )
              ],
            ),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const CartScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.admin_panel_settings, color: Colors.white),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          InkWell(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const WalletScreen()));
            },
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: const Color(0xFF1A365D),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('محفظة الفائق الامتيازات', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      SizedBox(height: 4),
                      Text('150,000 ر.ي', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Icon(Icons.account_balance_wallet, color: Colors.amber, size: 30),
                ],
              ),
            ),
          ),
          const SizedBox(height: 15),
          const Text('أقسام الخدمات الاحترافية', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A365D))),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: categories.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.85,
            ),
            itemBuilder: (context, index) {
              final cat = categories[index];
              return InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProductsScreen(categoryName: cat['name']),
                    ),
                  );
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 4, spreadRadius: 1)],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(cat['icon'], color: cat['color'], size: 28),
                      const SizedBox(height: 6),
                      Text(
                        cat['name'],
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 15),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.directions_bus, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('رحلات السفر والمسافرين: مأرب ➔ عدن', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('تتوقف الحافلة في استراحة شبوة بعد ساعتين.', style: TextStyle(fontSize: 11, color: Colors.black54)),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const TrackingMapScreen()));
                  },
                  icon: const Icon(Icons.map, size: 16),
                  label: const Text('تتبع خط السير على الخريطة الحية', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProductsScreen extends StatefulWidget {
  final String categoryName;
  const ProductsScreen({super.key, required this.categoryName});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> vendors = List.generate(10, (vIndex) {
      return {
        'name': 'متجر رقم (${vIndex + 1}) لـ ${widget.categoryName}',
        'rating': '4.${5 - (vIndex % 3)}',
        'time': '${10 + (vIndex * 3)} دقيقة',
        'products': List.generate(10, (pIndex) {
          return {
            'name': 'منتج أصلي (${pIndex + 1})',
            'price': (pIndex + 1) * 350 + 200,
            'desc': 'وصف عالي الجودة معتمد من متجر ${widget.categoryName} المميز',
          };
        }),
      };
    });

    return Scaffold(
      appBar: AppBar(
        title: Text('أسواق ${widget.categoryName}', style: const TextStyle(fontSize: 14, color: Colors.white)),
        backgroundColor: const Color(0xFF1A365D),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(10),
        itemCount: vendors.length,
        itemBuilder: (context, index) {
          final vendor = vendors[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ExpansionTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF1A365D),
                child: Text('${index + 1}', style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
              title: Text(vendor['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              subtitle: Text('التقييم: ${vendor['rating']} ⭐ | التوصيل: ${vendor['time']}', style: const TextStyle(fontSize: 10)),
              children: [
                const Divider(),
                ...List.generate((vendor['products'] as List).length, (pIdx) {
                  final prod = vendor['products'][pIdx];
                  return ListTile(
                    title: Text(prod['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    subtitle: Text('${prod['desc']}\nالسعر: ${prod['price']} ر.ي', style: const TextStyle(fontSize: 10)),
                    isThreeLine: true,
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A365D), foregroundColor: Colors.white),
                      onPressed: () {
                        setState(() {
                          CartModel.items.add({
                            'name': '${prod['name']} (${vendor['name']})',
                            'price': prod['price'],
                          });
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('تمت إضافة (${prod['name']}) إلى السلة. إجمالي السلة: ${CartModel.items.length} منتجات (${CartModel.totalAmount} ر.ي)'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      child: const Text('شراء', style: TextStyle(fontSize: 10)),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  String selectedPaymentMethod = 'cash_wallet';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سلة المشتريات والدفع الآمن', style: TextStyle(color: Colors.white, fontSize: 14)),
        backgroundColor: const Color(0xFF1A365D),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: CartModel.items.isEmpty
          ? const Center(
              child: Text(
                'السلة فارغة حالياً. أضف منتجات وابدأ التسوق!',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: CartModel.items.length,
                    itemBuilder: (context, index) {
                      final item = CartModel.items[index];
                      return ListTile(
                        leading: const Icon(Icons.shopping_bag, color: Color(0xFF1A365D)),
                        title: Text(item['name'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        subtitle: Text('السعر: ${item['price']} ر.ي', style: const TextStyle(fontSize: 11)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                          onPressed: () {
                            setState(() {
                              CartModel.items.removeAt(index);
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        value: selectedPaymentMethod,
                        decoration: const InputDecoration(
                          labelText: 'اختر المحفظة أو البنك اليمني للدفع',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'wallet_alfaeq', child: Text('محفظة الفائق الامتيازات (150,000 ر.ي)')),
                          DropdownMenuItem(value: 'kuraimi', child: Text('محفظة الكريمي بلس / الحساب الإلكتروني')),
                          DropdownMenuItem(value: 'jaib', child: Text('محفظة جيب (Jaib - بنك القطيبي)')),
                          DropdownMenuItem(value: 'cash_wallet', child: Text('محفظة كاش (Cash Wallet)')),
                          DropdownMenuItem(value: 'flous', child: Text('محفظة فلوس (Flous)')),
                          DropdownMenuItem(value: 'paisa', child: Text('محفظة بيس (Paisa / بيس)')),
                          DropdownMenuItem(value: 'shilin', child: Text('محفظة شلن (Shilin)')),
                          DropdownMenuItem(value: 'jawali', child: Text('محفظة جوالي / سبأفون كاش')),
                          DropdownMenuItem(value: 'yib', child: Text('موبايل موني - بنك اليمن الدولي (YIB)')),
                          DropdownMenuItem(value: 'tadamon', child: Text('فلوسك - البنك التضامن')),
                          DropdownMenuItem(value: 'cash', child: Text('الدفع النقدي عند الاستلام')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              selectedPaymentMethod = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'العدد: ${CartModel.items.length} | الإجمالي: ${CartModel.totalAmount} ر.ي',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('تأكيد الدفع الآمن'),
                                  content: Text(
                                      'تم خصم مبلغ ${CartModel.totalAmount} ر.ي بنجاح عبر المحفظة المختارة وإرسال الطلب للمتجر والمندوب!'),
                                  actions: [
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          CartModel.items.clear();
                                        });
                                        Navigator.pop(context);
                                        Navigator.pop(context);
                                      },
                                      child: const Text('حسناً'),
                                    )
                                  ],
                                ),
                              );
                            },
                            child: const Text('تأكيد وإتمام الدفع', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('محفظة الفائق وامتيازات التاجر', style: TextStyle(color: Colors.white, fontSize: 14)),
        backgroundColor: const Color(0xFF1A365D),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF1A365D), borderRadius: BorderRadius.circular(15)),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('الرصيد المتاح للعمليات:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  Text('150,000 ر.ي', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const ListTile(leading: Icon(Icons.history, color: Color(0xFF1A365D)), title: Text('سجل المعاملات والتحويلات المالية'), subtitle: Text('آخر عملية: إيداع ناجح 50,000 ر.ي')),
            const ListTile(leading: Icon(Icons.verified, color: Colors.green), title: Text('حساب تاجر معتمد'), subtitle: Text('تم تفعيل امتيازات المنصة الشاملة والمحافظ اليمنية')),
          ],
        ),
      ),
    );
  }
}

class TrackingMapScreen extends StatelessWidget {
  const TrackingMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تتبع الرحلة وخط السير الحي', style: TextStyle(color: Colors.white, fontSize: 14)),
        backgroundColor: const Color(0xFF1A365D),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          Container(
            color: Colors.blue.shade50,
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.map, size: 80, color: Colors.blue),
                  SizedBox(height: 10),
                  Text('جاري الاتصال بالأقمار الاصطناعية لتتبع الحافلة...', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  SizedBox(height: 5),
                  Text('خط السير: مأرب ➔ استراحة شبوة ➔ عدن', style: TextStyle(fontSize: 11, color: Colors.black54)),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)]),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('حالة الرحلة: تسير بانتظام 🟢', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  Text('السائق: أبو محمد', style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تسجيل الدخول وإدارة الصلاحيات', style: TextStyle(color: Colors.white, fontSize: 14)),
        backgroundColor: const Color(0xFF1A365D),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'نوع الصلاحية', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: '1', child: Text('المدير العام')),
                DropdownMenuItem(value: '2', child: Text('المدير المالي')),
                DropdownMenuItem(value: '3', child: Text('مدير البائعين والتجار')),
                DropdownMenuItem(value: '4', child: Text('مندوب / مندوب توصيل')),
                DropdownMenuItem(value: '5', child: Text('تاجر / صاحب متجر')),
              ],
              onChanged: (val) {},
            ),
            const SizedBox(height: 15),
            const TextField(decoration: InputDecoration(labelText: 'رقم الهاتف (اسم المستخدم)', border: OutlineInputBorder())),
            const SizedBox(height: 15),
            const TextField(obscureText: true, decoration: InputDecoration(labelText: 'كلمة المرور', border: OutlineInputBorder())),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A365D), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 45)),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل الدخول بنجاح وصلاحياتك مفعلة')));
              },
              child: const Text('دخول النظام'),
            ),
          ],
        ),
      ),
    );
  }
}
