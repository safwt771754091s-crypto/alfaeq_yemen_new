import 'package:flutter/material.dart';

import '../services/currency_service.dart';

/// Staff editor for the platform exchange rates. The catalog can hold prices in
/// any supported currency, so every rate here is "how many units of this
/// currency per 1 USD" and conversions pivot through USD.
class FxRatesPage extends StatefulWidget {
  const FxRatesPage({super.key});
  @override
  State<FxRatesPage> createState() => _FxRatesPageState();
}

class _FxRatesPageState extends State<FxRatesPage> {
  final _currency = CurrencyService.instance;
  final _controllers = <String, TextEditingController>{};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final code in CurrencyService.supported) {
      if (code == CurrencyService.usd) continue;
      _controllers[code] = TextEditingController(text: _fmt(_currency.rateFor(code)));
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  Future<void> _save() async {
    final next = <String, double>{CurrencyService.usd: 1};
    for (final entry in _controllers.entries) {
      final value = double.tryParse(entry.value.text.trim().replaceAll(',', '.'));
      if (value == null || value <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('سعر صرف غير صالح للعملة ${entry.key}.')));
        return;
      }
      next[entry.key] = value;
    }
    setState(() => _saving = true);
    try {
      await _currency.updateRates(next);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ أسعار الصرف وتحديثها فوراً.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حفظ الأسعار: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('أسعار الصرف', style: TextStyle(fontWeight: FontWeight.w900))),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: colors.primaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'الكتالوج يقبل التسعير بأي عملة مدعومة، والتحويل يتم عبر الدولار الأمريكي (USD) كعملة أساس. اكتب كم وحدة من كل عملة تساوي دولاراً واحداً.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (final code in CurrencyService.supported)
              if (code != CurrencyService.usd)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: _controllers[code],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: '1 USD = ? ${CurrencyService.labelFor(code)}',
                      suffixText: CurrencyService.symbolFor(code),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ الأسعار'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _saving ? null : () => setState(() {
                for (final entry in _controllers.entries) {
                  entry.value.text = _fmt(_currency.rateFor(entry.key));
                }
              }),
              icon: const Icon(Icons.refresh),
              label: const Text('إرجاع القيم الحالية'),
            ),
          ],
        ),
      ),
    );
  }
}
