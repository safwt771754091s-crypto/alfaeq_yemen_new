class AppDatabase {
  // محاكاة قاعدة البيانات المركزية للتطبيق
  static Map<String, dynamic> currentUser = {
    'name': 'المدير العام (صفوت محمد)',
    'role': 'admin', // admin, finance, vendor, customer
    'phone': '770000000',
    'balance': 150000.0,
  };

  static List<Map<String, dynamic>> categories = [
    {'title': 'الصيدليات والأدوية', 'icon': 'medical_services', 'color': 0xFFE53935},
    {'title': 'الرحلات والسفر', 'icon': 'directions_bus', 'color': 0xFFFB8C00},
    {'title': 'السوبرماركت', 'icon': 'shopping_basket', 'color': 0xFF43A047},
    {'title': 'المطاعم والوجبات', 'icon': 'restaurant', 'color': 0xFFE91E63},
    {'title': 'أدوات التجميل', 'icon': 'face', 'color': 0xFFAB47BC},
    {'title': 'الملابس والأزياء', 'icon': 'checkroom', 'color': 0xFFEC407A},
    {'title': 'توصيل مشاوير', 'icon': 'two_wheeler', 'color': 0xFF1E88E5},
    {'title': 'الشحن بين المدين', 'icon': 'local_shipping', 'color': 0xFF6D4C41},
  ];

  static List<Map<String, dynamic>> getProductsForVendor(String vendorName) {
    return [
      {'id': '1', 'name': '$vendorName - وجبة عائلية ممتازة', 'price': 4500, 'desc': 'وجبة طازجة مع الملحقات'},
      {'id': '2', 'name': '$vendorName - عرض خاص ومميز', 'price': 3000, 'desc': 'منتج معتمد بجودة عالية'},
      {'id': '3', 'name': '$vendorName - وجبة بروستد حار', 'price': 2500, 'desc': 'مقرمش مع البطاطس والمشروب'},
      {'id': '4', 'name': '$vendorName - بيتزا عائلية كبيرة', 'price': 5000, 'desc': 'جبنة موزاريلا إضافية'},
      {'id': '5', 'name': '$vendorName - عصير طبيعي طازج', 'price': 1200, 'desc': 'فواكه طبيعية 100%'},
      {'id': '6', 'name': '$vendorName - سلة تموينية أساسية', 'price': 15000, 'desc': 'متطلبات البيت الأساسية'},
      {'id': '7', 'name': '$vendorName - مشويات مشكلة فحم', 'price': 6000, 'desc': 'لحم طازج مشوي'},
      {'id': '8', 'name': '$vendorName - سندوتش شاورما صاروخ', 'price': 15000, 'desc': 'خلطة خاصة'},
      {'id': '9', 'name': '$vendorName - مخبوزات وحلويات يومية', 'price': 2000, 'desc': 'طازجة وساخنة'},
      {'id': '10', 'name': '$vendorName - كرتون مياه معدنية', 'price': 1000, 'desc': 'مياه نقية معقمة'},
    ];
  }
}

