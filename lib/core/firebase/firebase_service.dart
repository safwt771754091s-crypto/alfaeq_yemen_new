import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';

class FirebaseService {
  const FirebaseService._();

  static Future<void> initialize() async {
    if (!DefaultFirebaseOptions.isConfigured) {
      return;
    }

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}
