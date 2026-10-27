/// Role-specific entry points that a link can open directly.
///
/// The app decides the destination from the account's role, so a portal only
/// changes what the login screen says. This lets the owner share a
/// `.../#/merchant` or `.../#/driver` link that greets the right audience.
enum LoginPortal { merchant, driver }

/// Maps an app URL to the portal it should open, or `null` for the generic
/// login screen. Accepts a path/fragment (`#/merchant`, `#/driver`) or a query
/// parameter (`?portal=merchant`, `?mode=driver`, `?role=courier`).
LoginPortal? loginPortalFromUri(Uri uri) {
  final haystack = <String>[
    uri.fragment,
    uri.path,
    uri.queryParameters['portal'] ?? '',
    uri.queryParameters['mode'] ?? '',
    uri.queryParameters['role'] ?? '',
  ].join(' ').toLowerCase();

  const driverWords = ['driver', 'courier', 'delivery', 'مندوب', 'سائق'];
  const merchantWords = ['merchant', 'vendor', 'seller', 'store', 'تاجر', 'متجر'];
  if (driverWords.any(haystack.contains)) return LoginPortal.driver;
  if (merchantWords.any(haystack.contains)) return LoginPortal.merchant;
  return null;
}

extension LoginPortalLabels on LoginPortal {
  String get title =>
      this == LoginPortal.driver ? 'دخول المندوب (السائق)' : 'دخول التاجر';

  String get subtitle => this == LoginPortal.driver
      ? 'سجّل الدخول لاستلام مهام التوصيل ومتابعة أرباحك'
      : 'سجّل الدخول لإدارة متجرك وطلباتك';

  String get badge => this == LoginPortal.driver ? 'مندوب توصيل' : 'تاجر';
}
