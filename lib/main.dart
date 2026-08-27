import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:async';

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

class CartModel extends ChangeNotifier {
  static final CartModel instance = CartModel._internal();
  CartModel._internal();

  final List<Map<String, dynamic>> items = [];

  double get totalAmount {
    double sum = 0;
    for (var item in items) {
      sum += (item['price'] as num).toDouble();
    }
    return sum;
  }

  void addItem(Map<String, dynamic> item) {
    items.add(item);
    notifyListeners();
  }

  void removeItem(int index) {
    items.removeAt(index);
    notifyListeners();
  }

  void clear() {
    items.clear();
    notifyListeners();
  }
}

// شاشة الكاميرا الحقيقية لمسح QR Code
class QRScanScreen extends StatelessWidget {
  final Function(String) onScanned;
  const QRScanScreen({super.key, required this.onScanned});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مسح كود QR للمحفظة', style: TextStyle(color: Colors.white, fontSize: 14)),
        backgroundColor: const Color(0xFF1A365D),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: MobileScanner(
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            if (barcode.rawValue != null) {
              final code = barcode.rawValue!;
              onScanned(code);
              Navigator.pop(context);
              break;
            }
          }
        },
      ),
    );
  }
}

// شريط الإعلانات المتحركة (Banner Slider)
class AdsBannerSlider extends StatefulWidget {
  const AdsBannerSlider({super.key});

  @override
  State<AdsBannerSlider> createState() => _AdsBannerSliderState();
}

class _AdsBannerSliderState extends State<AdsBannerSlider> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  late Timer _timer;

  final List<Map<String, String>> ads = [
    {'title': 'عروض رحلات مأرب ➔ عدن', 'subtitle': 'احجز مقعدك الآن واحصل على خصم 20%'},
    {'title': 'توصيل مجاني للصيدليات', 'subtitle': 'أسرع خدمة توصيل أدوية في اليمن طوال الـ 24 ساعة'},
    {'title': 'محفظة الفائق الامتيازات', 'subtitle': 'ادفع بكل سهولة عبر جميع المحافظ اليمنية المعتمدة'},
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (Timer timer) {
      if (_currentPage < ads.length - 1) {
        _currentPage++;
      } else {
        _currentPage = 0;
      }
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      child: PageView.builder(
        controller: _pageController,
        itemCount: ads.length,
        itemBuilder: (context, index) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A365D), Color(0xFF2B6CB0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    const Icon(Icons.local_offer, color: Colors.amber, size: 18),
                    const SizedBox(width: 8),
                    Text(ads[index]['title']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(ads[index]['subtitle']!, style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          );
        },
      ),
    );
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
          const AdsBannerSlider(),
          const SizedBox(height: 12),
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
        ],
      ),
      floatingActionButton: AnimatedBuilder(
        animation: CartModel.instance,
        builder: (context, child) {
          if (CartModel.instance.items.isEmpty) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton.extended(
            backgroundColor: const Color(0xFF1A365D),
            foregroundColor: Colors.white,
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const CartScreen()));
            },
            icon: const Icon(Icons.shopping_cart, color: Colors.amber),
            label: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${CartModel.instance.items.length} أصناف في السلة',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                Text(
                  'الإجمالي: ${CartModel.instance.totalAmount} ر.ي',
                  style: const TextStyle(fontSize: 10, color: Colors.amberAccent),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class ProductsScreen extends StatelessWidget {
  final String categoryName;
  const ProductsScreen({super.key, required this.categoryName});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> vendors = List.generate(10, (vIndex) {
      return {
        'name': 'متجر رقم (${vIndex + 1}) لـ $categoryName',
        'rating': '4.${5 - (vIndex % 3)}',
        'time': '${10 + (vIndex * 3)} دقيقة',
        'products': List.generate(10, (pIndex) {
          return {
            'name': 'منتج أصلي (${pIndex + 1})',
            'price': (pIndex + 1) * 350 + 200,
            'desc': 'وصف عالي الجودة معتمد من متجر $categoryName المميز',
          };
        }),
      };
    });

    return Scaffold(
      appBar: AppBar(
        title: Text('أسواق $categoryName', style: const TextStyle(fontSize: 14, color: Colors.white)),
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
                        CartModel.instance.addItem({
                          'name': '${prod['name']} (${vendor['name']})',
                          'price': prod['price'],
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('تمت إضافة (${prod['name']}) إلى السلة. الإجمالي: ${CartModel.instance.totalAmount} ر.ي'),
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
  final TextEditingController accountController = TextEditingController();
  final TextEditingController pinController = TextEditingController();

  void _processPayment() {
    if (CartModel.instance.items.isEmpty) return;

    if (selectedPaymentMethod == 'cash') {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('تأكيد الطلب النقدي'),
          content: Text('تم تأكيد طلبك بنجاح بمبلغ ${CartModel.instance.totalAmount} ر.ي. الدفع سيكون نقداً عند الاستلام.'),
          actions: [
            TextButton(
              onPressed: () {
                CartModel.instance.clear();
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('حسناً'),
            )
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('التحقق من بيانات المحفظة الإلكترونية', style: TextStyle(fontSize: 14)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('أدخل رقم الحساب أو الهاتف المرتبط بالمحفظة والرمز السري للسحب الآمن:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 12),
                TextField(
                  controller: accountController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'رقم الحساب / رقم الهاتف (مثل: 77xxxxxxx)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'الرمز السري للمحفظة (PIN)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    // فتح شاشة كاميرا QR الحقيقية
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => QRScanScreen(
                          onScanned: (scannedCode) {
                            setState(() {
                              accountController.text = scannedCode;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('تم مسح الكود بنجاح: $scannedCode')),
                            );
                          },
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('فتح الكاميرا لمسح كود QR', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: () {
                if (accountController.text.isEmpty || pinController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('الرجاء إدخال رقم الحساب والرمز السري للمحفظة')),
                  );
                  return;
                }
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('تم الدفع بنجاح ✅'),
                    content: Text('تم خصم مبلغ ${CartModel.instance.totalAmount} ر.ي بنجاح من الحساب (${accountController.text}) وإرسال سند الصرف للمتجر!'),
                    actions: [
                      TextButton(
                        onPressed: () {
                          CartModel.instance.clear();
                          accountController.clear();
                          pinController.clear();
                          Navigator.pop(context);
                          Navigator.pop(context);
                        },
                        child: const Text('حسناً'),
                      )
                    ],
                  ),
                );
              },
              child: const Text('تأكيد وسحب المبلغ', style: TextStyle(fontSize: 11)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سلة المشتريات والدفع الآمن', style: TextStyle(color: Colors.white, fontSize: 14)),
        backgroundColor: const Color(0xFF1A365D),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: AnimatedBuilder(
        animation: CartModel.instance,
        builder: (context, child) {
          if (CartModel.instance.items.isEmpty) {
            return const Center(
              child: Text(
                'السلة فارغة حالياً. أضف منتجات وابدأ التسوق!',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            );
          }
          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: CartModel.instance.items.length,
                  itemBuilder: (context, index) {
                    final item = CartModel.instance.items[index];
                    return ListTile(
                      leading: const Icon(Icons.shopping_bag, color: Color(0xFF1A365D)),
                      title: Text(item['name'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      subtitle: Text('السعر: ${item['price']} ر.ي', style: const TextStyle(fontSize: 11)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                        onPressed: () {
                          CartModel.instance.removeItem(index);
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
                          'العدد: ${CartModel.instance.items.length} | الإجمالي: ${CartModel.instance.totalAmount} ر.ي',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                          onPressed: _processPayment,
                          child: const Text('متابعة الدفع الآمن', style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
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
