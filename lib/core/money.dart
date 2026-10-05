/// Trims trailing zeros so whole amounts stay compact while fractional catalog
/// prices keep their decimals (8.85 -> "8.85", 5.00 -> "5").
String formatAmount(num amount) {
  final value = amount.toDouble();
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// Formats a monetary amount with its currency (e.g. 8.85 -> "8.85 USD").
/// Returns [fallback] for a missing or non-positive amount.
String formatMoney(num? amount, String? currency, {String fallback = 'عند الطلب'}) {
  if (amount == null || amount <= 0) return fallback;
  return '${formatAmount(amount)} ${(currency ?? 'YER')}';
}
