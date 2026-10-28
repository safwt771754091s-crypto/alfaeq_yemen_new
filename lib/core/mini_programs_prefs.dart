import 'package:shared_preferences/shared_preferences.dart';

/// Remembers which mini-programs the user opened or starred, so the launcher
/// can surface "recently used" and "favorites" like WeChat does.
class MiniProgramsPrefs {
  const MiniProgramsPrefs._();

  static const _recentKey = 'mini_programs_recent';
  static const _favoriteKey = 'mini_programs_favorites';
  static const _maxRecent = 8;

  static Future<List<String>> recent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_recentKey) ?? const [];
  }

  static Future<List<String>> favorites() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_favoriteKey) ?? const [];
  }

  /// Moves [sectionId] to the front of the recent list (deduped, capped).
  static Future<void> markUsed(String sectionId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_recentKey) ?? <String>[];
    list.remove(sectionId);
    list.insert(0, sectionId);
    if (list.length > _maxRecent) list.removeRange(_maxRecent, list.length);
    await prefs.setStringList(_recentKey, list);
  }

  static Future<void> toggleFavorite(String sectionId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_favoriteKey) ?? <String>[];
    if (list.contains(sectionId)) {
      list.remove(sectionId);
    } else {
      list.add(sectionId);
    }
    await prefs.setStringList(_favoriteKey, list);
  }
}
