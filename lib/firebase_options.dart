// Generated manually from Firebase CLI output because flutterfire_cli failed
// while parsing firebase-tools output on this Windows environment.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return ios;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBajIGuAg8AHpSCCt69LNMhp4LTV934MfQ',
    appId: '1:344684384551:web:1f52db6b8d4e847a6e5902',
    messagingSenderId: '344684384551',
    projectId: 'smart-expense-431',
    authDomain: 'smart-expense-431.firebaseapp.com',
    storageBucket: 'smart-expense-431.firebasestorage.app',
    measurementId: 'G-FNSB0YQRY3',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDRyh0v0stOeekQZEjR1cd7Neplow_z3vU',
    appId: '1:344684384551:android:2d2d2802557960646e5902',
    messagingSenderId: '344684384551',
    projectId: 'smart-expense-431',
    storageBucket: 'smart-expense-431.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDTR4pEqcZJU-q1YuvW8oQh5KttNXLgXvA',
    appId: '1:344684384551:ios:47ec6b33cbaef1546e5902',
    messagingSenderId: '344684384551',
    projectId: 'smart-expense-431',
    storageBucket: 'smart-expense-431.firebasestorage.app',
    iosBundleId: 'com.example.smartexpense',
  );
}
