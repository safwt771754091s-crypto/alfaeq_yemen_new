enum AppRole {
  customer,
  merchant,
  driver,
  manager,
  admin,
}

extension AppRoleX on AppRole {
  String get key => switch (this) {
        AppRole.customer => 'customer',
        AppRole.merchant => 'merchant',
        AppRole.driver => 'driver',
        AppRole.manager => 'manager',
        AppRole.admin => 'admin',
      };

  String get label => switch (this) {
        AppRole.customer => 'عميل',
        AppRole.merchant => 'تاجر',
        AppRole.driver => 'موصل',
        AppRole.manager => 'مدير',
        AppRole.admin => 'مدير النظام',
      };

  static AppRole fromKey(String? value) {
    return AppRole.values.firstWhere(
      (role) => role.key == value,
      orElse: () => AppRole.customer,
    );
  }
}
