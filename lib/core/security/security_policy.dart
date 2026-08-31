class SecurityPolicy {
  const SecurityPolicy._();

  static const sessionTimeoutMinutes = 30;
  static const maxLoginAttempts = 5;
  static const requireAuthenticatedUser = true;
}
