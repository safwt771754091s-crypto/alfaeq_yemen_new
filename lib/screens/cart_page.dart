import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/product_units.dart';
import '../services/currency_service.dart';
import '../services/order_service.dart';
import '../services/supabase_service.dart';
import 'location_picker_page.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key});
  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _metadata = {};
  String _currency = 'USD';
  num _walletBalance = 0;
  String _walletCurrency = 'USD';
  List<String> _paymentProviders = const [];
  String get _uid => SupabaseService.client.auth.currentUser?.id ?? '';

  @override
  void initState() { super.initState(); _loadCart(); _loadWallet(); _loadPaymentProviders(); }

  Future<void> _loadPaymentProviders() async {
    try {
      final providers = await OrderService(preferSupabase: true).paymentProviders();
      if (mounted) setState(() => _paymentProviders = providers.where((p) => p != 'manual').toList());
    } catch (_) {/* online payments are optional */}
  }

  String _providerLabel(String provider) => switch (provider) {
        'stripe' => 'بطاقة (Stripe)',
        'paypal' => 'PayPal',
        _ => provider,
      };

  Future<void> _loadWallet() async {
    if (_uid.isEmpty) return;
    try {
      final info = await OrderService(preferSupabase: true).walletInfo();
      if (mounted) setState(() { _walletBalance = info.balance; _walletCurrency = info.currency; });
    } catch (_) {/* wallet display is best-effort */}
  }

  Future<void> _loadCart() async {
    if (_uid.isEmpty) { if (mounted) setState(() => _loading = false); return; }
    setState(() { _loading = true; _error = null; });
    try {
      if (!SupabaseService.isInitialized) {
        throw StateError('خدمة قاعدة البيانات غير مفعلة في هذا الإصدار.');
      }
      final row = await SupabaseService.client.from('carts').select('items,metadata').eq('uid', _uid).maybeSingle();
      final raw = row?['items'];
      _items = raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
      final meta = row?['metadata'];
      _metadata = meta is Map ? Map<String, dynamic>.from(meta) : <String, dynamic>{};
      _currency = _metadata['currency'] != null ? _metadata['currency'].toString() : (_items.isNotEmpty ? (_items.first['currency'] ?? 'USD').toString() : 'USD');
    } catch (e) {
      _error = 'تعذر تحميل السلة من الخادم: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  ProductUnit _unit(Map<String, dynamic> item) => ProductUnit.fromId((item['saleUnit'] ?? item['sale_unit'] ?? 'piece').toString());

  num _quantity(Map<String, dynamic> item) {
    final unit = _unit(item);
    final base = item['quantityBase'] ?? item['quantity_base'];
    if (base is num) return unit.fromBase(base);
    return item['quantity'] is num ? item['quantity'] as num : 1;
  }

  num get _total {
    num total = 0;
    for (final item in _items) {
      final price = item['price'];
      if (price is num) total += price * _quantity(item);
    }
    return total;
  }

  String get _displayCurrency => CurrencyService.instance.displayCurrency;
  bool get _baseIsUsd => _currency.toUpperCase() == 'USD';
  num get _displayTotal => _baseIsUsd ? CurrencyService.instance.convert(_total.toDouble(), _displayCurrency) : _total;
  num get _payTotal => _walletCurrency == _currency ? _total : CurrencyService.instance.convert(_total.toDouble(), _walletCurrency);
  bool get _walletCovers {
    if (_walletCurrency == _currency) return _walletBalance >= _total;
    // Cross-currency debit only applies to USD-priced carts (the catalog base).
    if (!_baseIsUsd) return false;
    return _walletBalance >= _payTotal;
  }

  Future<void> _saveItems(List<Map<String, dynamic>> items, {String? checkoutKey}) async {
    if (!SupabaseService.isInitialized || _uid.isEmpty) return;
    final metadata = <String, dynamic>{
      'currency': items.isNotEmpty ? (items.first['currency'] ?? _currency) : _currency,
      // A new cart shape invalidates the previous checkout idempotency key.
      if (checkoutKey != null) 'checkout_key': checkoutKey,
    };
    await SupabaseService.client.from('carts').upsert({
      'uid': _uid,
      'owner_id': _uid,
      'items': items,
      'metadata': metadata,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'uid');
    if (mounted) setState(() { _items = items; _metadata = metadata; });
  }

  Future<void> _changeQuantity(int index, int direction) async {
    if (_busy || index < 0 || index >= _items.length) return;
    final item = Map<String, dynamic>.from(_items[index]);
    final unit = _unit(item);
    final rawStep = item['stepBase'] ?? item['step_base'];
    final step = rawStep is num ? rawStep.round() : unit.defaultStepBase;
    final rawBase = item['quantityBase'] ?? item['quantity_base'];
    final currentBase = rawBase is num ? rawBase.round() : unit.toBase(_quantity(item)).round();
    final nextBase = currentBase + direction * step;
    final next = _items.map((e) => Map<String, dynamic>.from(e)).toList();
    if (nextBase <= 0) {
      next.removeAt(index);
    } else {
      item['quantityBase'] = nextBase;
      item['quantity'] = unit.fromBase(nextBase);
      next[index] = item;
    }
    setState(() => _busy = true);
    try { await _saveItems(next); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحديث السلة: $e'))); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _remove(int index) async {
    if (_busy || index < 0 || index >= _items.length) return;
    final next = _items.map((e) => Map<String, dynamic>.from(e)).toList()..removeAt(index);
    setState(() => _busy = true);
    try { await _saveItems(next); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حذف الصنف: $e'))); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _checkout() async {
    if (_busy || _items.isEmpty || _uid.isEmpty) return;
    final addressController = TextEditingController();
    String paymentMethod = 'cash_on_delivery';
    LatLng? deliveryPoint;
    // The wallet holds one currency; only offer wallet payment when it matches the cart.
    final walletCovers = _walletCovers;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إتمام الطلب'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: addressController, maxLines: 3, decoration: const InputDecoration(labelText: 'عنوان التوصيل', hintText: 'الحي، الشارع، معلم قريب')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: paymentMethod,
              decoration: const InputDecoration(labelText: 'طريقة الدفع'),
              items: [
                const DropdownMenuItem(value: 'cash_on_delivery', child: Text('الدفع عند الاستلام')),
                DropdownMenuItem(
                  value: 'wallet',
                  child: Text('محفظة الفائق (رصيدك: ${CurrencyService.instance.formatNative(_walletBalance, _walletCurrency)} — المطلوب: ${CurrencyService.instance.formatNative(_payTotal, _walletCurrency)})'),
                ),
                for (final p in _paymentProviders)
                  DropdownMenuItem(value: 'online_$p', child: Text('الدفع الإلكتروني (${_providerLabel(p)})')),
              ],
              onChanged: (v) => setDialogState(() => paymentMethod = v ?? 'cash_on_delivery'),
            ),
            if (paymentMethod == 'wallet' && !walletCovers) ...[
              const SizedBox(height: 8),
              Text('رصيد المحفظة غير كافٍ لهذا الطلب. اشحن المحفظة أو اختر الدفع عند الاستلام.',
                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final point = await Navigator.push<LatLng>(context, MaterialPageRoute(builder: (_) => const LocationPickerPage(title: 'تحديد موقع التوصيل')));
                if (point != null) setDialogState(() => deliveryPoint = point);
              },
              icon: Icon(deliveryPoint == null ? Icons.location_on_outlined : Icons.location_on),
              label: Text(deliveryPoint == null ? 'حدد موقع التوصيل على الخريطة' : 'تم تحديد الموقع'),
            ),
            if (deliveryPoint != null) Text('${deliveryPoint!.latitude.toStringAsFixed(6)}, ${deliveryPoint!.longitude.toStringAsFixed(6)}', textDirection: TextDirection.ltr),
            const SizedBox(height: 8),
            Text('الإجمالي: ${CurrencyService.instance.formatNative(_displayTotal, _displayCurrency)}', style: const TextStyle(fontWeight: FontWeight.w900)),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
            FilledButton(
              onPressed: (paymentMethod == 'wallet' && !walletCovers) ? null : () => Navigator.pop(dialogContext, true),
              child: const Text('تأكيد الطلب'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) { addressController.dispose(); return; }
    final typed = addressController.text.trim();
    final address = typed.isNotEmpty ? typed : (deliveryPoint == null ? '' : 'موقع الخريطة: ${deliveryPoint!.latitude.toStringAsFixed(6)}, ${deliveryPoint!.longitude.toStringAsFixed(6)}');
    addressController.dispose();
    if (address.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب العنوان أو حدد الموقع على الخريطة.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final service = OrderService(preferSupabase: true);
      final isOnline = paymentMethod.startsWith('online_');
      final provider = isOnline ? paymentMethod.substring('online_'.length) : null;
      final orderId = paymentMethod == 'wallet'
          ? await service.createPaidOrder(
              items: _items,
              address: address,
              idempotencyKey: await _ensureCheckoutKey(),
              currency: _walletCurrency,
              latitude: deliveryPoint?.latitude,
              longitude: deliveryPoint?.longitude,
            )
          : isOnline
              ? await service.createPendingOrder(
                  items: _items,
                  address: address,
                  provider: provider!,
                  latitude: deliveryPoint?.latitude,
                  longitude: deliveryPoint?.longitude,
                )
              : await service.createOrder(
                  customerId: _uid,
                  items: _items,
                  address: address,
                  paymentMethod: paymentMethod,
                  latitude: deliveryPoint?.latitude,
                  longitude: deliveryPoint?.longitude,
                );
      // Checkout clears the Supabase cart atomically inside create_order.
      if (mounted) setState(() => _items = []);
      if (!mounted) return;

      var message = paymentMethod == 'wallet' ? 'تم الخصم من محفظة الفائق.' : 'الدفع عند الاستلام.';
      if (isOnline) {
        final intent = await service.createPaymentIntent(orderId: orderId, provider: provider);
        final ref = intent['providerRef']?.toString() ?? '';
        final approveUrl = intent['approveUrl']?.toString() ?? '';
        final paid = ref.isEmpty ? false : await service.confirmPayment(orderId: orderId, providerRef: ref, provider: provider);
        message = paid
            ? 'تم الدفع إلكترونياً بنجاح.'
            : approveUrl.isNotEmpty
                ? 'تم إنشاء الطلب. أكمل الدفع عبر الرابط: $approveUrl'
                : 'تم إنشاء الطلب. بانتظار تأكيد الدفع الإلكتروني.';
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('تم إنشاء الطلب'),
          content: Text('رقم الطلب: $orderId\n$message\n'
              'تم التحقق من المنتجات والمخزون وتسعير الطلب من الخادم.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('حسناً'))],
        ),
      );
      _loadWallet();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إنشاء الطلب: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A stable key for the current cart contents. It is persisted in the cart
  /// metadata so a retry after a dropped response returns the same order
  /// instead of charging twice; the next cart change generates a fresh key.
  Future<String> _ensureCheckoutKey() async {
    final existing = _metadata['checkout_key']?.toString();
    if (existing != null && existing.isNotEmpty) return existing;
    final key = 'co_${_uid}_${DateTime.now().microsecondsSinceEpoch}';
    await _saveItems(_items, checkoutKey: key);
    return key;
  }

  @override
  Widget build(BuildContext context) {
    if (_uid.isEmpty) return const Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: Center(child: Text('يجب تسجيل الدخول أولاً.'))));
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('سلة التسوق', style: TextStyle(fontWeight: FontWeight.w900)), actions: [IconButton(onPressed: _busy ? null : _loadCart, icon: const Icon(Icons.refresh))]),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
                : _items.isEmpty
                    ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.shopping_cart_outlined, size: 72), SizedBox(height: 12), Text('السلة فارغة', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)), SizedBox(height: 6), Text('أضف منتجاً من المتاجر ليظهر هنا.')]))
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          ..._items.asMap().entries.map((entry) {
                            final index = entry.key;
                            final item = entry.value;
                            final unit = _unit(item);
                            final quantity = _quantity(item);
                            final price = item['price'] is num ? item['price'] as num : 0;
                            final name = (item['name'] ?? 'منتج').toString();
                            return Card(child: ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.shopping_bag_outlined)),
                              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w900)),
                              subtitle: Text('$quantity ${unit.label} × ${CurrencyService.instance.formatProduct(item)}/${unit.label} = ${CurrencyService.instance.format(price.toDouble() * quantity)}'),
                              trailing: SizedBox(width: 150, child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                IconButton(onPressed: _busy ? null : () => _changeQuantity(index, -1), icon: const Icon(Icons.remove_circle_outline)),
                                Text('$quantity', style: const TextStyle(fontWeight: FontWeight.w900)),
                                IconButton(onPressed: _busy ? null : () => _changeQuantity(index, 1), icon: const Icon(Icons.add_circle_outline)),
                                IconButton(onPressed: _busy ? null : () => _remove(index), icon: const Icon(Icons.delete_outline)),
                              ])),
                            ));
                          }),
                          const SizedBox(height: 10),
                          Card(child: ListTile(title: const Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.w900)), trailing: Text(CurrencyService.instance.formatNative(_displayTotal, _displayCurrency), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)))),
                          const SizedBox(height: 14),
                          SizedBox(height: 52, child: FilledButton.icon(onPressed: _busy ? null : _checkout, icon: const Icon(Icons.shopping_cart_checkout), label: const Text('إتمام الطلب والشراء', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)))),
                        ],
                      ),
      ),
    );
  }
}
