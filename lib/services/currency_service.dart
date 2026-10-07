import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/money.dart';
import 'supabase_service.dart';

/// Platform display currency + FX rates.
///
/// Catalog prices are stored in USD (the base currency). The customer picks a
/// display currency (USD / SAR / YER) and every price is converted with the
/// platform rates stored server-side (`settings.fx_rates`, editable by staff).
/// Defaults are used until the server responds so the UI never blocks.
class CurrencyService extends ChangeNotifier {
  CurrencyService._();
  static final CurrencyService instance = CurrencyService._();

  static const String usd = 'USD';
  static const String sar = 'SAR';
  static const String yer = 'YER';
  static const List<String> supported = [usd, sar, yer];

  static const String _prefsKey = 'display_currency';

  /// Kept in sync with the server rates (base USD): 1 USD = 3.75 SAR = 1537.5 YER.
  static const Map<String, double> defaultRates = {usd: 1, sar: 3.75, yer: 1537.5};

  String _display = usd;
  Map<String, double> _rates = Map<String, double>.from(defaultRates);
  bool _loaded = false;

  String get displayCurrency => _display;
  Map<String, double> get rates => Map.unmodifiable(_rates);
  bool get isLoaded => _loaded;
  double rateFor(String code) => _rates[_normalize(code)] ?? 1;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _display = _normalize(prefs.getString(_prefsKey));
    } catch (_) {/* fall back to the default display currency */}
    await refreshRates();
    _loaded = true;
    notifyListeners();
  }

  Future<void> refreshRates() async {
    if (!SupabaseService.isInitialized) return;
    try {
      final data = await SupabaseService.client.rpc('get_fx_rates');
      if (data is Map && data['rates'] is Map) {
        _rates = {
          for (final entry in (data['rates'] as Map).entries)
            entry.key.toString().toUpperCase(): (entry.value as num).toDouble(),
        };
        notifyListeners();
      }
    } catch (_) {/* keep the last good rates */}
  }

  /// Staff-only: persist new platform rates server-side and refresh the cache.
  Future<void> updateRates(Map<String, double> rates) async {
    if (!SupabaseService.isInitialized) throw StateError('الخادم غير متصل.');
    final payload = {
      'rates': {for (final e in rates.entries) e.key.toUpperCase(): e.value},
    };
    await SupabaseService.client.rpc('set_fx_rates', params: {'p_rates': payload});
    await refreshRates();
  }

  Future<void> setDisplayCurrency(String code) async {
    final next = _normalize(code);
    if (next == _display) return;
    _display = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, next);
    } catch (_) {/* selection still applies for this session */}
    notifyListeners();
  }

  /// Converts an amount from [from] into [to] using the USD-based rates.
  double convertBetween(double amount, String from, String to) {
    final f = _normalize(from);
    final t = _normalize(to);
    if (f == t) return _round(amount);
    return _round(amount * rateFor(t) / rateFor(f));
  }

  /// Converts a base-USD amount into [code] and formats it (e.g. "33,579 ر.ي").
  String format(double usdAmount, {String? currency}) =>
      formatNative(convert(usdAmount, currency ?? _display), currency ?? _display);

  /// Formats an amount that is already denominated in [code].
  String formatNative(num amount, String code) =>
      '${formatAmount(_round(amount.toDouble()))} ${symbolFor(code)}';

  /// Formats a product price by converting its own currency into the selected
  /// display currency (catalog rows may be priced in SAR, USD, or YER).
  String formatProduct(Map product, {String fallback = 'عند الطلب'}) {
    final price = product['price'];
    if (price is! num) return fallback;
    final src = _normalize((product['currency'] ?? usd).toString());
    return formatNative(convertBetween(price.toDouble(), src, _display), _display);
  }

  double convert(double usdAmount, String code) => _round(usdAmount * rateFor(code));

  /// Matches the server (`private.fx_convert`, round to 2 decimals) so the
  /// amount shown is exactly the amount charged.
  double _round(double value) => (value * 100).round() / 100;

  static String symbolFor(String code) {
    switch (code.toUpperCase()) {
      case sar:
        return 'ر.س';
      case yer:
        return 'ر.ي';
      case usd:
      default:
        return '\$';
    }
  }

  static String labelFor(String code) {
    switch (code.toUpperCase()) {
      case sar:
        return 'ريال سعودي';
      case yer:
        return 'ريال يمني';
      case usd:
      default:
        return 'دولار أمريكي';
    }
  }

  String _normalize(String? code) {
    final up = (code ?? usd).toUpperCase();
    return supported.contains(up) ? up : usd;
  }
}
