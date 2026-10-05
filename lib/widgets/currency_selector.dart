import 'package:flutter/material.dart';

import '../services/currency_service.dart';

/// Compact currency selector used in app bars and account screens.
class CurrencySelector extends StatelessWidget {
  const CurrencySelector({super.key, this.dark = false});

  final bool dark;

  Future<void> _choose(BuildContext context) async {
    final service = CurrencyService.instance;
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('عملة العرض', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ),
          for (final code in CurrencyService.supported)
            ListTile(
              onTap: () => Navigator.pop(sheetContext, code),
              leading: Icon(code == service.displayCurrency ? Icons.radio_button_checked : Icons.radio_button_unchecked),
              title: Text('${CurrencyService.labelFor(code)} (${CurrencyService.symbolFor(code)})'),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text('تُحوَّل الأسعار من الدولار بسعر الصرف المعتمد لدى المنصة.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
          ),
        ]),
      ),
    );
    if (selected != null) await service.setDisplayCurrency(selected);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: CurrencyService.instance,
      builder: (context, _) {
        final code = CurrencyService.instance.displayCurrency;
        final color = dark ? Colors.white : const Color(0xFF0B1B3A);
        return TextButton(
          onPressed: () => _choose(context),
          style: TextButton.styleFrom(foregroundColor: color, padding: const EdgeInsets.symmetric(horizontal: 10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.language, size: 18, color: color),
            const SizedBox(width: 4),
            Text(CurrencyService.symbolFor(code), style: TextStyle(color: color, fontWeight: FontWeight.w900)),
          ]),
        );
      },
    );
  }
}
