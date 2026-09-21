class ProductUnit {
  final String id;
  final String label;
  final String baseUnit;
  final int scale;
  final int defaultStepBase;

  const ProductUnit(this.id, this.label, this.baseUnit, this.scale, this.defaultStepBase);

  static const piece = ProductUnit('piece', 'قطعة', 'piece', 1, 1);
  static const kg = ProductUnit('kg', 'كجم', 'g', 1000, 250);
  static const g = ProductUnit('g', 'جرام', 'g', 1, 50);
  static const l = ProductUnit('l', 'لتر', 'ml', 1000, 250);
  static const ml = ProductUnit('ml', 'مل', 'ml', 1, 50);
  static const m = ProductUnit('m', 'متر', 'm', 1, 1);

  static const List<ProductUnit> all = [piece, kg, g, l, ml, m];

  static ProductUnit fromId(String id) {
    switch (id) {
      case 'kg':
        return kg;
      case 'g':
        return g;
      case 'l':
        return l;
      case 'ml':
        return ml;
      case 'm':
        return m;
      case 'piece':
      default:
        return piece;
    }
  }

  static ProductUnit fromProduct(Map<String, dynamic> product) {
    final unitId = (product['saleUnit'] ?? product['unit'] ?? 'piece').toString();
    return fromId(unitId);
  }

  static int stockBase(Map<String, dynamic> product) {
    final explicit = (product['stockBase'] is num) ? (product['stockBase'] as num).round() : null;
    if (explicit != null) return explicit;
    final scale = Number.fromString(product['unitScale']?.toString() ?? '1');
    final stock = (product['stock'] is num) ? (product['stock'] as num).toDouble() : 0.0;
    if (stock <= 0) return 0;
    final normalizedScale = scale > 0 ? scale : 1;
    return (stock * normalizedScale).round();
  }

  static num fromBase(int baseValue) {
    final unit = this;
    return baseValue / unit.scale;
  }

  int fromBase(int value) => value ~/ scale;

  static String formatBase(Map<String, dynamic> product, int baseValue) {
    final unit = fromProduct(product);
    final base = baseValue;
    if (unit.id == 'kg' || unit.id == 'l') {
      final floatValue = (base / unit.scale);
      return '${floatValue.toStringAsFixed(floatValue >= 100 ? 0 : 2)} ${unit.label}';
    }
    return '$base ${unit.label}';
  }
}

extension NumberFromString on num {
  static int fromString(String value) {
    final parsed = num.tryParse(value);
    return parsed != null && parsed.isFinite ? parsed.round() : 1;
  }
}
