import 'package:shared_preferences/shared_preferences.dart';

class AppStorage {
  const AppStorage._();

  static const _authenticatedKey = 'auth.isAuthenticated';

  static Future<void> setAuthenticated(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_authenticatedKey, value);
  }

  static Future<bool> isAuthenticated() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_authenticatedKey) ?? false;
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authenticatedKey);
  }
}
