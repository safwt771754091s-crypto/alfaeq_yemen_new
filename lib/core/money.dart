/// Trims trailing zeros so whole amounts stay compact while fractional catalog
/// prices keep their decimals (8.85 -> "8.85", 5.00 -> "5"). Integers of four
/// or more digits are grouped for readability (33579 -> "33,579") while shorter
/// amounts are left untouched.
String formatAmount(num amount, {bool grouping = true}) {
  final value = amount.toDouble();
  final text = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return grouping ? _group(text) : text;
}

String _group(String text) {
  final negative = text.startsWith('-');
  final body = negative ? text.substring(1) : text;
  final dot = body.indexOf('.');
  final intPart = dot == -1 ? body : body.substring(0, dot);
  final rest = dot == -1 ? '' : body.substring(dot);
  final buffer = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(',');
    buffer.write(intPart[i]);
  }
  return '${negative ? '-' : ''}$buffer$rest';
}

/// Formats a monetary amount with its currency (e.g. 8.85 -> "8.85 USD").
/// Returns [fallback] for a missing or non-positive amount.
String formatMoney(num? amount, String? currency, {String fallback = 'عند الطلب'}) {
  if (amount == null || amount <= 0) return fallback;
  return '${formatAmount(amount)} ${(currency ?? 'YER')}';
}
