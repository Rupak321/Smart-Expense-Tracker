import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Removes a user's data, and optionally the account itself.
///
/// Signing out was the only way to leave: the records stayed in Firestore
/// indefinitely and the account could not be closed from inside the app.
class AccountDeletionService {
  AccountDeletionService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Firestore caps a batch at 500 operations, so deletes are chunked well
  /// below that rather than assuming a small collection.
  static const _batchLimit = 400;

  /// Every subcollection written under users/{uid}.
  ///
  /// Firestore cannot enumerate subcollections from a mobile client, so this
  /// list has to be kept in step with the services that write them. Missing
  /// one would leave orphaned documents behind with no way to reach them.
  static const _subcollections = [
    'data',
    'budgets',
    'categories',
    'bill_reminders',
    'ai_sessions',
    'settings',
    'recurringExpenses',
  ];

  /// Deletes all of the signed-in user's stored records.
  ///
  /// The account itself is left in place, so this is the "start over" path.
  static Future<void> wipeData() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('User must be logged in to delete their data.');
    }

    final root = _firestore.collection('users').doc(uid);

    for (final name in _subcollections) {
      await _deleteCollection(root.collection(name));
    }

    await root.delete();
  }

  static Future<void> _deleteCollection(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    while (true) {
      final snapshot = await collection.limit(_batchLimit).get();
      if (snapshot.docs.isEmpty) return;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      // A partial page means that was the last of them.
      if (snapshot.docs.length < _batchLimit) return;
    }
  }

  /// Deletes the records and then closes the account.
  ///
  /// Returns null on success, or a message to show. Firebase refuses to delete
  /// an account whose sign-in is not recent, which is a security rule rather
  /// than a fault - the caller is told to sign in again rather than shown a
  /// raw error.
  static Future<String?> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      return 'You are not signed in.';
    }

    try {
      await wipeData();
    } catch (e) {
      debugPrint('Data wipe failed: $e');
      return 'Could not remove your data, so the account was left in place.';
    }

    try {
      await user.delete();
      await GoogleSignIn().signOut();
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        // The data is already gone at this point, which is the part that
        // cannot be undone. Say so plainly rather than implying nothing
        // happened.
        return 'Your data has been deleted. To close the account itself, '
            'sign out, sign in again, and repeat this from the account page.';
      }
      return e.message ?? 'Could not close the account.';
    } catch (e) {
      debugPrint('Account deletion failed: $e');
      return 'Could not close the account.';
    }
  }
}
