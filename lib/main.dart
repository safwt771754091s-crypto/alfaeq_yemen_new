import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/app_sections.dart';
import 'screens/admin_dashboard.dart';
import 'screens/auth_gate.dart';
import 'screens/cart_page.dart';
import 'screens/developer_page.dart';
import 'screens/merchant_invite_page.dart';
import 'screens/my_orders_page.dart';
import 'screens/notifications_page.dart';
import 'services/auth_service.dart';
import 'services/currency_service.dart';
import 'services/push_service.dart';
import 'services/supabase_service.dart';
import 'services/catalog_service.dart';

import 'core/product_units.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Object? startupError;
  StackTrace? startupStack;

  // A dropped connection at launch must not brick the app. Retry the Supabase
  // bootstrap before surfacing the fatal error screen.
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      await SupabaseService.initialize();
      startupError = null;
      startupStack = null;
      break;
    } catch (error, stackTrace) {
      startupError = error;
      startupStack = stackTrace;
      if (attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
  }

  // Load the saved display currency + platform FX rates; never blocks startup.
  try {
    await CurrencyService.instance.load();
  } catch (_) {/* fall back to defaults */}

  runApp(AlfaeqYemenApp(
    startupError: startupError,
    startupStack: startupStack,
  ));
}

class AlfaeqYemenApp extends StatefulWidget {
  final Object? startupError;
  final StackTrace? startupStack;

  const AlfaeqYemenApp({
    super.key,
    this.startupError,
    this.startupStack,
  });

  @override
  State<AlfaeqYemenApp> createState() => _AlfaeqYemenAppState();
}

class _AlfaeqYemenAppState extends State<AlfaeqYemenApp> {
  Object? _startupError;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _startupError = widget.startupError;
    _registerPushOnAuth();
  }

  void _registerPushOnAuth() {
    if (!SupabaseService.isInitialized) return;
    SupabaseService.client.auth.onAuthStateChange.listen((event) {
      if (event.session != null) PushService.instance.registerCurrentDevice();
    });
    PushService.instance.registerCurrentDevice();
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    Object? error;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await SupabaseService.initialize();
        error = null;
        break;
      } catch (e) {
        error = e;
        if (attempt < 2) {
          await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _startupError = error;
      _retrying = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_startupError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'الفائق يمن',
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(title: const Text('الفائق يمن')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off_rounded, size: 56, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'تعذر الاتصال بخادم الفائق يمن.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'تأكد من اتصالك بالإنترنت ثم أعد المحاولة.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _retrying ? null : _retry,
                      icon: _retrying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(_retrying ? 'جارٍ الاتصال…' : 'إعادة المحاولة'),
                    ),
                    const SizedBox(height: 16),
                    SelectableText(
                      'تفاصيل: $_startupError',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'الفائق يمن',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF0B6E4F), scaffoldBackgroundColor: const Color(0xFFF7F9F8)),
        home: _initialHome(),
      );
  }

  Widget _initialHome() {
    if (kIsWeb) {
      final token = Uri.base.queryParameters['merchant_invite'];
      if (token != null && token.isNotEmpty) return RootBackGuard(child: MerchantInvitePage(token: token));
    }
    return RootBackGuard(child: const AuthGate());
  }
}


/// يمنع الخروج غير المقصود من التطبيق عند الضغط على زر الرجوع في الصفحة الجذر.
/// الضغطة الأولى تُظهر تنبيهًا، والضغطة الثانية خلال ثانيتين تُغلق التطبيق.
class RootBackGuard extends StatefulWidget {
  final Widget child;

  const RootBackGuard({super.key, required this.child});

  @override
  State<RootBackGuard> createState() => _RootBackGuardState();
}

class _RootBackGuardState extends State<RootBackGuard> {
  DateTime? _lastBackPress;

  Future<void> _handleBack() async {
    final now = DateTime.now();
    final last = _lastBackPress;
    if (last != null && now.difference(last) <= const Duration(seconds: 2)) {
      await SystemNavigator.pop();
      return;
    }

    _lastBackPress = now;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('اضغط مرة أخرى خلال ثانيتين للخروج من التطبيق.'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !kIsWeb) {
          _handleBack();
        }
      },
      child: widget.child,
    );
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
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: SupabaseService.client.auth.currentUser == null || !SupabaseService.isInitialized
                    ? null
                    : SupabaseService.client
                        .from('carts')
                        .stream(primaryKey: ['uid'])
                        .eq('uid', SupabaseService.client.auth.currentUser!.id),
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
              IconButton(tooltip: 'الإشعارات', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage())), icon: const Icon(Icons.notifications_none)),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'cart') Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage()));
                  if (value == 'orders') Navigator.push(context, MaterialPageRoute(builder: (_) => const MyOrdersPage()));
                  if (value == 'admin') _openAdmin(context);
                  if (value == 'developer') _openDeveloper(context);
                  if (value == 'logout') _signOut(context);
                },
                itemBuilder: (_) => const [
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
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يجب تسجيل الدخول أولاً.')));
      return;
    }
    try {
      await const CatalogService().addToCart(user.id, product);
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
                          Text('${CurrencyService.instance.formatNative(num.tryParse('$price') ?? 0, '$currency'.toUpperCase() == 'USD' ? CurrencyService.instance.displayCurrency : '$currency')} / ${unit.label}', style: const TextStyle(fontWeight: FontWeight.w900)),
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
