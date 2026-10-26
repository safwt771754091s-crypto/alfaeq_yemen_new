/// Canonical platform permission catalog.
///
/// Mirrors the `public.permissions_catalog` table so the owner UI can label
/// every permission even before the table is reachable. The database remains
/// the source of truth for what is actually granted.
class PermissionCatalog {
  final String id;
  final String label;
  final String category;
  const PermissionCatalog(this.id, this.label, this.category);

  static const all = <PermissionCatalog>[
    PermissionCatalog('admin.dashboard', 'لوحة الإدارة', 'admin'),
    PermissionCatalog('admin.users.manage', 'إدارة الحسابات والصلاحيات', 'admin'),
    PermissionCatalog('admin.merchants.approve', 'اعتماد التجار', 'admin'),
    PermissionCatalog('admin.payouts.review', 'مراجعة المستحقات والمدفوعات', 'admin'),
    PermissionCatalog('wallet.deposits.review', 'مراجعة إيداعات المحفظة', 'wallet'),
    PermissionCatalog('wallet.deposits.reject', 'رفض إيداعات المحفظة', 'wallet'),
    PermissionCatalog('wallet.withdraw.review', 'مراجعة طلبات السحب', 'wallet'),
    PermissionCatalog('wallet.adjust', 'تعديل أرصدة المحافظ', 'wallet'),
    PermissionCatalog('wallet.vouchers.manage', 'إدارة رموز شحن المحفظة', 'wallet'),
    PermissionCatalog('products.manage', 'إدارة الأصناف', 'catalog'),
    PermissionCatalog('products.bulk_import', 'استيراد الأصناف من Excel', 'catalog'),
    PermissionCatalog('products.review', 'مراجعة واعتماد الأصناف', 'catalog'),
    PermissionCatalog('sections.manage', 'إدارة الأقسام', 'catalog'),
    PermissionCatalog('merchants.manage', 'إدارة التجار والمتاجر', 'merchants'),
    PermissionCatalog('merchants.approve', 'اعتماد المتاجر', 'merchants'),
    PermissionCatalog('merchants.invites', 'دعوات التجار والروابط', 'merchants'),
    PermissionCatalog('orders.manage', 'إدارة الطلبات', 'orders'),
    PermissionCatalog('orders.dispatch', 'التوزيع وإسناد الطلبات', 'orders'),
    PermissionCatalog('orders.refund', 'الاسترجاع وإلغاء الطلبات', 'orders'),
    PermissionCatalog('payments.review', 'مراجعة الحوالات والدفع', 'orders'),
    PermissionCatalog('drivers.manage', 'إدارة المندوبين', 'drivers'),
    PermissionCatalog('drivers.approve', 'اعتماد طلبات المندوبين', 'drivers'),
    PermissionCatalog('delivery.zones.manage', 'مناطق وأسعار التوصيل', 'drivers'),
    PermissionCatalog('content.reels', 'إدارة الفيديو القصير', 'content'),
    PermissionCatalog('content.live', 'إدارة غرف البث المباشر', 'content'),
    PermissionCatalog('content.updates', 'تحديثات الصفحة الرئيسية', 'content'),
    PermissionCatalog('automation.manage', 'أتمتة المنصة', 'automation'),
    PermissionCatalog('whatsapp.automation', 'أتمتة واتساب', 'automation'),
    PermissionCatalog('ai.assistant', 'مساعد ذكاء الفائق', 'ai'),
    PermissionCatalog('ai.operations', 'تشغيل مهام الذكاء الاصطناعي', 'ai'),
    PermissionCatalog('platform.settings', 'إعدادات المنصة', 'platform'),
    PermissionCatalog('platform.bank_accounts.manage', 'إدارة الحسابات البنكية', 'platform'),
    PermissionCatalog('platform.fx_rates', 'أسعار الصرف', 'platform'),
    PermissionCatalog('platform.mini_programs', 'البرامج المصغرة', 'platform'),
    PermissionCatalog('developer.center', 'مركز المطور', 'developer'),
    PermissionCatalog('developer.security_audit', 'الفحص الأمني والتدقيق', 'developer'),
  ];

  static final Map<String, String> _labels = <String, String>{
    for (final p in all) p.id: p.label,
  };

  static String labelFor(String permission) => _labels[permission] ?? permission;

  static const categoryLabels = <String, String>{
    'admin': 'الإدارة',
    'wallet': 'المحافظ والمالية',
    'catalog': 'الكتالوج والأصناف',
    'merchants': 'التجار والمتاجر',
    'orders': 'الطلبات والتوزيع',
    'drivers': 'المندوبون والتوصيل',
    'content': 'المحتوى والبث',
    'automation': 'الأتمتة',
    'ai': 'الذكاء الاصطناعي',
    'platform': 'المنصة والإعدادات',
    'developer': 'المطور والأمن',
  };

  /// Permission ids grouped by category, in catalog order.
  static Map<String, List<PermissionCatalog>> get byCategory {
    final grouped = <String, List<PermissionCatalog>>{};
    for (final p in all) {
      grouped.putIfAbsent(p.category, () => []).add(p);
    }
    return grouped;
  }
}
