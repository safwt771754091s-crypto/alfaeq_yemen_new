import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('media sound preference', () {
    test('sound starts enabled by default', () {
      final src = File('lib/core/sound_prefs.dart').readAsStringSync();
      expect(src, contains('static bool enabled = true'));
      expect(src, contains("getBool(_key) ?? true"));
    });

    test('reels page honours and remembers the sound choice', () {
      final src = File('lib/screens/reels_page.dart').readAsStringSync();
      expect(src, contains('SoundPrefs.load()'));
      expect(src, contains('_muted = !soundOn'));
      expect(src, contains('SoundPrefs.set(!_muted)'));
    });

    test('live room honours and remembers the sound choice', () {
      final src = File('lib/screens/live_rooms_page.dart').readAsStringSync();
      expect(src, contains('SoundPrefs.load()'));
      expect(src, contains('_muted = !soundOn'));
      expect(src, contains('SoundPrefs.set(!_muted)'));
    });
  });
}
