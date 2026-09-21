import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase configuration bootstrap for local builds.
///
/// CI replaces this file with the project-specific output from
/// `flutterfire configure`. For local builds, provide the values below with
/// `--dart-define`, for example:
///
/// flutter run -d chrome \
///   --dart-define=FIREBASE_API_KEY=... \
///   --dart-define=FIREBASE_APP_ID=... \
///   --dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
///   --dart-define=FIREBASE_PROJECT_ID=alfaeq-yemen-fed37
///
/// Never commit production credentials or secrets to this file.
class DefaultFirebaseOptions {
  static const String _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String _messagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const String _projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'alfaeq-yemen-fed37',
  );
  static const String _storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
    defaultValue: 'alfaeq-yemen-fed37.firebasestorage.app',
  );
  static const String _authDomain = String.fromEnvironment(
    'FIREBASE_AUTH_DOMAIN',
    defaultValue: 'alfaeq-yemen-fed37.firebaseapp.com',
  );

  static FirebaseOptions get currentPlatform {
    if (_apiKey.isEmpty || _appId.isEmpty || _messagingSenderId.isEmpty) {
      throw StateError(
        'Firebase configuration is missing. Run flutterfire configure or '
        'provide FIREBASE_API_KEY, FIREBASE_APP_ID, and '
        'FIREBASE_MESSAGING_SENDER_ID with --dart-define.',
      );
    }

    if (kIsWeb) return web;
    return mobile;
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: _apiKey,
    appId: _appId,
    messagingSenderId: _messagingSenderId,
    projectId: _projectId,
    authDomain: _authDomain,
    storageBucket: _storageBucket,
  );

  static const FirebaseOptions mobile = FirebaseOptions(
    apiKey: _apiKey,
    appId: _appId,
    messagingSenderId: _messagingSenderId,
    projectId: _projectId,
    storageBucket: _storageBucket,
  );
}
