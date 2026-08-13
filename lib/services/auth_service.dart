import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'user_data_service.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: _googleClientId,
    serverClientId: _googleServerClientId,
  );

  static String? get _googleClientId {
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return '344684384551-asp0u2tb5e1vh3s7prlf6pf9fctpfpkh.apps.googleusercontent.com';
    }
    return null;
  }

  static String? get _googleServerClientId {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return '344684384551-132g82gmps0mclmq6uttrchkvfgqn1qf.apps.googleusercontent.com';
    }
    return null;
  }

  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  static User? get currentUser => _auth.currentUser;

  static bool get isLoggedIn => currentUser != null;

  static Future<String?> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await UserDataService.saveAuthUserProfileIfMissing();
      return null;
    } on FirebaseAuthException catch (e) {
      return _messageFromException(e);
    } catch (e) {
      debugPrint('Sign in failed: $e');
      return 'Unable to sign in right now.';
    }
  }

  static Future<String?> registerWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await credential.user?.updateDisplayName(name.trim());
      await credential.user?.reload();
      await UserDataService.saveAuthUserProfileIfMissing();
      return null;
    } on FirebaseAuthException catch (e) {
      return _messageFromException(e);
    } catch (e) {
      debugPrint('Registration failed: $e');
      return 'Unable to create an account right now.';
    }
  }

  static Future<String?> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return null;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await _auth.signInWithCredential(credential);
      await UserDataService.saveAuthUserProfileIfMissing();
      return null;
    } on FirebaseAuthException catch (e) {
      return _messageFromException(e);
    } on PlatformException catch (e) {
      debugPrint('Google sign in platform failure: ${e.code} ${e.message}');
      return _messageFromGooglePlatformException(e);
    } catch (e) {
      debugPrint('Google sign in failed: $e');
      return 'Unable to sign in with Google right now.';
    }
  }

  /// Sends a reset link. Returns null on success, or a message to show.
  ///
  /// Deliberately reports success even when no account exists, so the screen
  /// cannot be used to discover which email addresses are registered.
  static Future<String?> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        return null;
      }
      return _messageFromException(e);
    } catch (e) {
      debugPrint('Password reset failed: $e');
      return 'Unable to send the reset email right now.';
    }
  }

  static Future<void> logout() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  static String _messageFromException(FirebaseAuthException e) {
    switch (e.code) {
      case 'channel-error':
      case 'network-request-failed':
        return 'Check your internet connection and try again.';
      case 'invalid-credential':
        return 'The email or password is incorrect.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
        return 'No account found for that email.';
      case 'wrong-password':
        return 'The password is incorrect.';
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'weak-password':
        return 'Choose a stronger password.';
      case 'operation-not-allowed':
        return 'This sign-in provider is not enabled in Firebase.';
      default:
        return e.message ?? 'Authentication failed.';
    }
  }

  static String _messageFromGooglePlatformException(PlatformException e) {
    switch (e.code) {
      case 'sign_in_failed':
        return 'Google sign-in failed. Check that Google provider and Android SHA fingerprints are configured in Firebase.';
      case 'network_error':
        return 'Check your internet connection and try Google sign-in again.';
      default:
        return e.message ?? 'Unable to sign in with Google right now.';
    }
  }
}
