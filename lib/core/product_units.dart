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
    final explicit = product['stockBase'];
    if (explicit is num && explicit.isFinite) {
      return explicit.round();
    }

    final unit = fromProduct(product);
    final rawStock = product['stock'];
    final unitScale = product['unitScale'] is num
        ? (product['unitScale'] as num).toInt()
        : unit.scale;

    if (rawStock is num && rawStock.isFinite) {
      return (rawStock * unitScale).round();
    }
    return 0;
  }

  int toBase(dynamic value) {
    if (value is num && value.isFinite) {
      return (value * scale).round();
    }
    if (value is String) {
      final parsed = num.tryParse(value);
      if (parsed != null && parsed.isFinite) {
        return (parsed * scale).round();
      }
    }
    return 0;
  }

  num toDisplay(int baseValue) => baseValue / scale;

  static String formatBase(Map<String, dynamic> product, int baseValue) {
    final unit = fromProduct(product);
    final value = unit.toDisplay(baseValue);
    if (unit.id == 'kg' || unit.id == 'l') {
      return '${value.toStringAsFixed(value >= 100 ? 0 : 2)} ${unit.label}';
    }
    return '$baseValue ${unit.label}';
  }
}
