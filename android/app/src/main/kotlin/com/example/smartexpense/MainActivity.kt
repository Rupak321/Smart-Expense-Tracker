package com.example.smartexpense

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity rather than FlutterActivity: the biometric prompt
// used by the app lock is a fragment, and it cannot attach to a plain
// FlutterActivity. With the wrong base class the lock compiles, installs and
// then fails only at the moment the user tries to unlock.
class MainActivity : FlutterFragmentActivity()
