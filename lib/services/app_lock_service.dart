import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Requires the device's own biometric or PIN before the app opens.
///
/// A financial app with a full transaction history had no lock of its own, so
/// anyone holding an unlocked phone could read the lot.
///
/// The preference is stored on the device rather than in Firestore on purpose:
/// it protects this handset, it must be readable before the user is
/// authenticated, and it should not follow the account onto someone else's
/// phone.
class AppLockService {
  AppLockService._();

  static const _enabledKey = 'app_lock_enabled';

  static final LocalAuthentication _auth = LocalAuthentication();

  static bool _enabled = false;

  /// True once the user has passed the lock for this session.
  static bool _unlockedThisSession = false;

  static bool get isEnabled => _enabled;

  static bool get needsUnlock => _enabled && !_unlockedThisSession;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledKey) ?? false;
    } catch (e) {
      debugPrint('App lock preference unreadable: $e');
      _enabled = false;
    }
  }

  /// Whether this device can actually lock.
  ///
  /// Covers both a fingerprint or face and a device PIN or pattern, so a phone
  /// with no biometric hardware can still use the lock.
  static Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (e) {
      debugPrint('Local auth unavailable: $e');
      return false;
    }
  }

  /// What the device offers, for describing the setting honestly.
  static Future<String> describeAvailable() async {
    try {
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face)) return 'Face unlock or device PIN';
      if (types.contains(BiometricType.fingerprint) ||
          types.contains(BiometricType.strong)) {
        return 'Fingerprint or device PIN';
      }
      return 'Device PIN or pattern';
    } catch (_) {
      return 'Device PIN or pattern';
    }
  }

  /// Prompts for authentication. True when the user passed.
  static Future<bool> authenticate({
    String reason = 'Unlock SmartExpense',
  }) async {
    try {
      final passed = await _auth.authenticate(
        localizedReason: reason,
        // The device PIN is a valid fallback: requiring biometrics alone would
        // lock out anyone whose fingerprint reader is wet or unreadable.
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      if (passed) _unlockedThisSession = true;
      return passed;
    } catch (e) {
      debugPrint('Authentication failed: $e');
      return false;
    }
  }

  /// Turning the lock on requires passing it once first.
  ///
  /// Otherwise a mis-set lock could shut the owner out of their own records
  /// on the next launch, with no way back in.
  static Future<bool> setEnabled(bool enabled) async {
    if (enabled) {
      final passed = await authenticate(
        reason: 'Confirm it is you before turning on the app lock',
      );
      if (!passed) return false;
    }

    _enabled = enabled;
    _unlockedThisSession = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, enabled);
    } catch (e) {
      debugPrint('Could not save app lock preference: $e');
    }
    return true;
  }

  /// Called when the app goes to the background, so returning asks again.
  static void lock() {
    if (_enabled) _unlockedThisSession = false;
  }

  @visibleForTesting
  static void resetForTest({bool enabled = false, bool unlocked = false}) {
    _enabled = enabled;
    _unlockedThisSession = unlocked;
  }
}
