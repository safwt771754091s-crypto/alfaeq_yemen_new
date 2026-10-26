import 'package:shared_preferences/shared_preferences.dart';

/// Remembers whether short-video / live audio should start playing.
/// Sound is ON by default; toggling the mute button remembers the choice.
class SoundPrefs {
  const SoundPrefs._();

  static const _key = 'media_sound_enabled';

  static bool enabled = true;
  static bool _loaded = false;

  static Future<bool> load() async {
    if (_loaded) return enabled;
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool(_key) ?? true;
    _loaded = true;
    return enabled;
  }

  static Future<void> set(bool value) async {
    enabled = value;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}
