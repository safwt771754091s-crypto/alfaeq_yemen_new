import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/app_sections.dart';
import 'firebase_options.dart';
import 'screens/admin_dashboard.dart';
import 'screens/ai_assistant_page.dart';
import 'screens/auth_gate.dart';
import 'screens/cart_page.dart';
import 'screens/developer_page.dart';
import 'screens/merchant_invite_page.dart';
import 'screens/my_orders_page.dart';
import 'services/auth_service.dart';
import 'services/supabase_service.dart';
import 'services/catalog_service.dart';

import 'core/product_units.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AlfaeqBootstrapApp());
}

class AlfaeqBootstrapApp extends StatefulWidget {
  const AlfaeqBootstrapApp({super.key});

  @override
  State<AlfaeqBootstrapApp> createState() => _AlfaeqBootstrapAppState();
}

class _AlfaeqBootstrapAppState extends State<AlfaeqBootstrapApp> {
  late final Future<void> _startup;

  @override
  void initState() {
    super.initState();
    _startup = _initializeServices();
  }

  Future<void> _initializeServices() async {
    await SupabaseService.initialize();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // One-time migration reset: the current release changed the auth/data
    // path. Clear any persisted legacy session so testing starts from a clean
    // login screen. New logins are not affected on subsequent launches.
    final prefs = await SharedPreferences.getInstance();
    const migrationKey = 'alfaeq_auth_migration_2026_09_22_2';
    if (prefs.getBool(migrationKey) != true) {
      await FirebaseAuth.instance.signOut();
      try {
        if (SupabaseService.isInitialized) {
          await SupabaseService.client.auth.signOut();
        }
      } catch (_) {}
      await prefs.setBool(migrationKey, true);
    }

    if (kIsWeb) {
      const siteKey = String.fromEnvironment('RECAPTCHA_ENTERPRISE_SITE_KEY');
      if (siteKey.isNotEmpty) {
        try {
          await FirebaseAppCheck.instance.activate(
            providerWeb: ReCaptchaEnterpriseProvider(siteKey),
          );
        } catch (e) {
          debugPrint('Web App Check activation failed: $e');
        }
      }
    } else {
      try {
        await FirebaseAppCheck.instance.activate(
          providerAndroid: const AndroidPlayIntegrityProvider(),
          providerApple: const AppleAppAttestProvider(),
        );
      } catch (e) {
        debugPrint('Mobile App Check activation failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                appBar: AppBar(title: const Text('الفائق يمن')),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: SelectableText(
                      'تعذر تشغيل خدمات الفائق يمن.\\n\\nخطأ التهيئة: ${snapshot.error}\\n\\nأعد تحميل الصفحة. إذا استمر الخطأ، أرسل لنا صورة هذه الشاشة.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return const AlfaeqYemenApp();
      },
    );
  }
}

class AlfaeqYemenApp extends StatelessWidget {
  const AlfaeqYemenApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'الفائق يمن',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF0B6E4F), scaffoldBackgroundColor: const Color(0xFFF7F9F8)),
        home: _initialHome(),
      );

  Widget _initialHome() {
    if (kIsWeb) {
      final token = Uri.base.queryParameters['merchant_invite'];
      if (token != null && token.isNotEmpty) return MerchantInvitePage(token: token);
    }
    return const AuthGate();
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> _openAdmin(BuildContext context) async {
    final allowed = await AuthService().hasAdminClaim();
    if (!context.mounted) return;
    if (allowed) Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboard()));
    else ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('هذه المنطقة مخصصة للمشرفين فقط.')));
  }

  Future<void> _openDeveloper(BuildContext context) async {
    final role = await AuthService().role();
    final admin = await AuthService().hasAdminClaim();
    if (!context.mounted) return;
    if (admin || role == 'developer') Navigator.push(context, MaterialPageRoute(builder: (_) => const DeveloperPage()));
    else ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا تملك صلاحية صفحة المطور.')));
  }

  Future<void> _signOut(BuildContext context) async => AuthService().signOut();

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('الفائق يمن', style: TextStyle(fontWeight: FontWeight.w900)),
            actions: [
              IconButton(tooltip: 'ذكاء الفائق', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiAssistantPage())), icon: const Icon(Icons.auto_awesome)),
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: FirebaseAuth.instance.currentUser == null || !SupabaseService.isInitialized
                    ? null
                    : SupabaseService.client
                        .from('carts')
                        .stream(primaryKey: ['uid'])
                        .eq('uid', FirebaseAuth.instance.currentUser!.uid),
                builder: (context, snapshot) {
                  var count = 0;
                  final rows = snapshot.data ?? const <Map<String, dynamic>>[];
                  final raw = rows.isNotEmpty ? rows.first['items'] : null;
                  if (raw is List) {
                    for (final item in raw) {
                      if (item is Map) {
                        final quantity = item['quantity'];
                        count += quantity is num ? quantity.round() : 0;
                      }
                    }
                  }
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        tooltip: 'السلة',
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage())),
                        icon: const Icon(Icons.shopping_cart_outlined),
                      ),
                      if (count > 0)
                        Positioned(
                          right: 2,
                          top: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              count > 99 ? '99+' : '$count',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              IconButton(tooltip: 'طلباتي', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyOrdersPage())), icon: const Icon(Icons.receipt_long_outlined)),
              IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none)),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'ai') Navigator.push(context, MaterialPageRoute(builder: (_) => const AiAssistantPage()));
                  if (value == 'cart') Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage()));
                  if (value == 'orders') Navigator.push(context, MaterialPageRoute(builder: (_) => const MyOrdersPage()));
                  if (value == 'admin') _openAdmin(context);
                  if (value == 'developer') _openDeveloper(context);
                  if (value == 'logout') _signOut(context);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'ai', child: ListTile(leading: Icon(Icons.auto_awesome), title: Text('ذكاء الفائق'))),
                  PopupMenuItem(value: 'cart', child: ListTile(leading: Icon(Icons.shopping_cart_outlined), title: Text('السلة'))),
                  PopupMenuItem(value: 'orders', child: ListTile(leading: Icon(Icons.receipt_long_outlined), title: Text('طلباتي وتتبع الطلبات'))),
                  PopupMenuItem(value: 'admin', child: ListTile(leading: Icon(Icons.admin_panel_settings_outlined), title: Text('لوحة الإدارة'))),
                  PopupMenuItem(value: 'developer', child: ListTile(leading: Icon(Icons.code), title: Text('صفحة المطور'))),
                  PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout), title: Text('تسجيل الخروج'))),
                ],
                icon: const Icon(Icons.account_circle_outlined),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(decoration: InputDecoration(hintText: 'ابحث عن متجر أو منتج أو خدمة...', prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none))),
              const SizedBox(height: 16),
              InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiAssistantPage())),
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), color: const Color(0xFF0B6E4F)),
                  child: const Row(children: [Icon(Icons.auto_awesome, color: Colors.white, size: 34), SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('مرحباً بك في الفائق يمن', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)), SizedBox(height: 8), Text('منصة عالمية تبدأ من اليمن — اسأل ذكاء الفائق عن الخدمات والبحث والتخطيط.', style: TextStyle(color: Colors.white70))]))]),
                ),
              ),
              const SizedBox(height: 24),
              const Text('الأقسام الـ16', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: appSections.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.08),
                itemBuilder: (context, index) {
                  final section = appSections[index];
                  return Card(
                    elevation: 0,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SectionPage(section: section))),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_icon(section.icon), size: 36, color: const Color(0xFF0B6E4F)),
                            const SizedBox(height: 10),
                            Text(section.title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 5),
                            Text(section.subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );

  static IconData _icon(String name) => switch (name) {
        'storefront' => Icons.storefront_outlined,
        'restaurant' => Icons.restaurant_outlined,
        'pharmacy' => Icons.local_pharmacy_outlined,
        'beauty' => Icons.face_retouching_natural,
        'construction' => Icons.construction_outlined,
        'car' => Icons.directions_car_outlined,
        'flight' => Icons.flight_takeoff_outlined,
        'hotel' => Icons.hotel_outlined,
        'account_balance' => Icons.account_balance_outlined,
        'handyman' => Icons.handyman_outlined,
        'devices' => Icons.devices_outlined,
        'home' => Icons.home_work_outlined,
        'work' => Icons.work_outline,
        'school' => Icons.school_outlined,
        'medical' => Icons.medical_services_outlined,
        _ => Icons.explore_outlined,
      };
}

class SectionPage extends StatefulWidget {
  final AppSection section;
  const SectionPage({super.key, required this.section});

  @override
  State<SectionPage> createState() => _SectionPageState();
}

class _SectionPageState extends State<SectionPage> {
  final _catalog = const CatalogService();

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: Text(widget.section.title)),
          body: FutureBuilder<List<CatalogDocument>>(
            future: _catalog.approvedStores(widget.section.id),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('تعذر قراءة المتاجر: ${snapshot.error}', textAlign: TextAlign.center),
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final stores = snapshot.data ?? const <CatalogDocument>[];
              if (stores.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(widget.section.title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text(widget.section.subtitle),
                    const SizedBox(height: 24),
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.store_outlined),
                        title: Text('لا يوجد تجار معتمدون بعد'),
                        subtitle: Text('سيظهر المتجر هنا مباشرة بعد حفظه واعتماده في قاعدة البيانات.'),
                      ),
                    ),
                  ],
                );
              }
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(widget.section.title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(widget.section.subtitle),
                  const SizedBox(height: 18),
                  ...stores.map((store) => _StoreCatalogCard(store: store)),
                ],
              );
            },
          ),
        ),
      );
}

class _StoreCatalogCard extends StatelessWidget {
  final CatalogDocument store;
  const _StoreCatalogCard({required this.store});

  Future<void> _addToCart(BuildContext context, CatalogDocument product) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يجب تسجيل الدخول أولاً.')));
      return;
    }
    try {
      await const CatalogService().addToCart(user.uid, product);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تمت إضافة «${product.data['name'] ?? 'الصنف'}» إلى السلة.'),
            action: SnackBarAction(
              label: 'فتح السلة',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage())),
            ),
          ),
        );
      }
    } on StateError catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } on FirebaseException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إضافة الصنف للسلة: ${e.message ?? e.code}')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إضافة الصنف للسلة: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = store.data;
    final storeId = store.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.storefront_outlined)),
            title: Text('${data['name'] ?? 'متجر'}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            subtitle: Text('${data['address'] ?? ''} • ${data['phone'] ?? ''}'),
          ),
          const Divider(),
          FutureBuilder<List<CatalogDocument>>(
            future: const CatalogService().activeProducts(storeId: storeId, limit: 5000),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
              if (snapshot.hasError) return Text('تعذر تحميل الأصناف: ${snapshot.error}');
              final products = snapshot.data ?? const <CatalogDocument>[];
              if (products.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('لا توجد أصناف مضافة لهذا المتجر بعد.'),
                );
              }
              return Column(
                children: products.map((product) {
                  final p = product.data;
                  final stockBase = ProductUnit.stockBase(p);
                  final unit = ProductUnit.fromProduct(p);
                  final price = p['price'] ?? 0;
                  final currency = p['currency'] ?? 'YER';
                  return Card(
                    elevation: 0,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      leading: Builder(
                        builder: (context) {
                          final imageUrl = (p['image_url'] ?? p['imageUrl'] ?? p['image'] ?? '').toString();
                          if (imageUrl.isEmpty) {
                            return CircleAvatar(child: Icon(stockBase > 0 ? Icons.inventory_2_outlined : Icons.remove_shopping_cart_outlined));
                          }
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              imageUrl,
                              width: 54,
                              height: 54,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => CircleAvatar(child: Icon(stockBase > 0 ? Icons.inventory_2_outlined : Icons.remove_shopping_cart_outlined)),
                            ),
                          );
                        },
                      ),
                      title: Text('${p['name'] ?? 'صنف'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${p['description'] ?? ''}\nالمتوفر: ${ProductUnit.formatBase(p, stockBase)}', maxLines: 3, overflow: TextOverflow.ellipsis),
                      isThreeLine: true,
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('$price $currency / ${unit.label}', style: const TextStyle(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 5),
                          SizedBox(
                            height: 34,
                            child: FilledButton.icon(
                              onPressed: stockBase > 0 ? () => _addToCart(context, product) : null,
                              icon: const Icon(Icons.add_shopping_cart, size: 18),
                              label: Text(stockBase > 0 ? 'أضف للسلة' : 'نفد'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ]),
      ),
    );
  }
}
